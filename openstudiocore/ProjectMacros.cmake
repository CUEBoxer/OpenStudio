include(CMakeParseArguments)

if(NOT USE_PCH)
  macro(AddPCH TARGET_NAME)
  endmacro()
endif()

# Add google tests macro
macro(ADD_GOOGLE_TESTS executable)
  foreach(source ${ARGN})
    if(NOT "${source}" MATCHES "/moc_.*cpp")
      string(REGEX MATCH .*cpp source "${source}")
      if(source)
        file(READ "${source}" contents)
        string(REGEX MATCHALL "TEST_?F?\\(([A-Za-z_0-9 ,]+)\\)" found_tests ${contents})
        foreach(hit ${found_tests})
          string(REGEX REPLACE ".*\\(([A-Za-z_0-9]+)[, ]*([A-Za-z_0-9]+)\\).*" "\\1.\\2" test_name ${hit})
          add_test(${test_name} "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${executable}" --gtest_filter=${test_name})
        endforeach()
      endif()
    endif()
  endforeach()
endmacro()

# Create source groups automatically based on file path
macro(CREATE_SRC_GROUPS SRC)
  foreach(F ${SRC})
    string(REGEX MATCH "(^.*)([/\\].*$)" M ${F})
    if(CMAKE_MATCH_1)
      string(REGEX REPLACE "[/\\]" "\\\\" DIR ${CMAKE_MATCH_1})
      source_group(${DIR} FILES ${F})
    else()
      source_group(\\ FILES ${F})
    endif()
  endforeach()
endmacro()

# Create test targets
macro(CREATE_TEST_TARGETS BASE_NAME SRC DEPENDENCIES)
  if(BUILD_TESTING)
    add_executable(${BASE_NAME}_tests ${SRC})

    list(APPEND ALL_TESTING_TARGETS "${BASE_NAME}_tests")
    set(ALL_TESTING_TARGETS "${ALL_TESTING_TARGETS}" PARENT_SCOPE)


    CREATE_SRC_GROUPS("${SRC}")

    get_target_property(BASE_NAME_TYPE ${BASE_NAME} TYPE)
    if("${BASE_NAME_TYPE}" STREQUAL "EXECUTABLE")
      # don't link base name
      set(ALL_DEPENDENCIES ${DEPENDENCIES})
    else()
      # also link base name
      set(ALL_DEPENDENCIES ${BASE_NAME} ${DEPENDENCIES})
    endif()

    target_link_libraries(${BASE_NAME}_tests
      gtest
      gtest_main
      ${ALL_DEPENDENCIES}
    )

    ADD_GOOGLE_TESTS(${BASE_NAME}_tests ${SRC})
    add_dependencies("${BASE_NAME}_tests" "${BASE_NAME}_resources")

    if(ENABLE_TEST_RUNNER_TARGETS)
      add_custom_target(${target_name}_run_tests
        COMMAND ${BASE_NAME}_tests
        DEPENDS ${target_name}_tests
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
      )
    endif()

    AddPCH(${BASE_NAME}_tests)

    ## suppress deprecated warnings in unit tests
    if(UNIX)
      set_target_properties(${ALL_TESTING_TARGETS} PROPERTIES COMPILE_FLAGS "-Wno-deprecated-declarations")
    elseif(MSVC)
      set_target_properties(${ALL_TESTING_TARGETS} PROPERTIES COMPILE_FLAGS "/wd4996")
    endif()

  endif()
endmacro()


macro(MAKE_LITE_SQL_TARGET IN_FILE BASE_FILE)
  set(cmake_script "
    file(READ \"${CMAKE_CURRENT_BINARY_DIR}/${BASE_FILE}.cpp\" text)
    string(REPLACE ${BASE_FILE}.hpp ${BASE_FILE}.hxx modified_text \"\${text}\")
    file(WRITE \"${CMAKE_CURRENT_BINARY_DIR}/${BASE_FILE}.cxx\" \"\${modified_text}\")
  ")
  file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/${BASE_FILE}fix.cmake" ${cmake_script})
  add_custom_command(OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/${BASE_FILE}.hxx" "${CMAKE_CURRENT_BINARY_DIR}/${BASE_FILE}.cxx"
    COMMAND "${LITESQL_GEN_EXE}" --output-dir="${CMAKE_CURRENT_BINARY_DIR}" --target=c++ "${CMAKE_CURRENT_SOURCE_DIR}/${IN_FILE}"
    COMMAND "${CMAKE_COMMAND}" -E rename "${CMAKE_CURRENT_BINARY_DIR}/${BASE_FILE}.hpp" "${CMAKE_CURRENT_BINARY_DIR}/${BASE_FILE}.hxx"
    COMMAND "${CMAKE_COMMAND}" -P "${CMAKE_CURRENT_BINARY_DIR}/${BASE_FILE}fix.cmake"
    COMMAND "${CMAKE_COMMAND}" -E remove -f "${CMAKE_CURRENT_BINARY_DIR}/${BASE_FILE}.cpp"
    DEPENDS litesql-gen "${CMAKE_CURRENT_SOURCE_DIR}/${IN_FILE}"
  )
endmacro()


# add a swig target
# KEY_I_FILE should include path, see src/utilities/CMakeLists.txt.
macro(MAKE_SWIG_TARGET NAME SIMPLENAME KEY_I_FILE I_FILES PARENT_TARGET PARENT_SWIG_TARGETS)
  set(DEPENDS "${PARENT_TARGET}")
  set(SWIG_DEFINES "")
  set(SWIG_COMMON "")

  ##
  ## Begin collection of requirements to reduce SWIG regenerations
  ## and fix parallel build issues
  ##


  # Get all of the source files for the parent target this SWIG library is wrapping
  get_target_property(target_files ${PARENT_TARGET} SOURCES)

  foreach(f ${target_files})
    # Get the extension of the source file
    get_source_file_property(p "${f}" LOCATION)
    get_filename_component(extension "${p}" EXT)

    # If it's a header file ("*.h*") add it to the list of headers
    if("${extension}" MATCHES "\\.h.*")
      if("${extension}" MATCHES "\\..xx")
        list(APPEND GeneratedHeaders "${p}")
      else()
        list(APPEND RequiredHeaders "${p}")
      endif()
    endif()
  endforeach()


  # Now, append all of the .i* files provided to the macro to the
  # list of required headers.
  foreach(i ${I_FILES})
    get_source_file_property(p "${i}" LOCATION)
    get_filename_component(extension "${p}" EXT)
    if("${extension}" MATCHES "\\..xx")
      list(APPEND GeneratedHeaders "${p}")
    else()
      list(APPEND RequiredHeaders "${p}")
    endif()
  endforeach()

  # RequiredHeaders now represents all of the headers and .i files that all
  # of the SWIG targets generated by this macro call rely on.
  # And GeneratedHeaders contains all .ixx and .hxx files needed to make
  # these SWIG targets

  set(ParentSWIGWrappers "")
  # Now we loop through all of the parent swig targets and collect the requirements from them
  foreach(p ${PARENT_SWIG_TARGETS})
    get_target_property(target_files "ruby_${p}" SOURCES)

    if("${target_files}" STREQUAL "target_files-NOTFOUND")
      message(FATAL_ERROR "Unable to locate sources for ruby_${p}, there is probably an error in the build order for ${NAME} in the top level CMakeLists.txt or you have not properly specified the dependencies in MAKE_SWIG_TARGET for ${NAME}")
    endif()

    #message(STATUS "${target_files}")
    # This is the real data collection
    list(APPEND ParentSWIGWrappers ${${p}_SWIG_Depends})
  endforeach()


  # Reduce the size of the RequiredHeaders list
  list(REMOVE_DUPLICATES RequiredHeaders)

  if(GeneratedHeaders)
    list(REMOVE_DUPLICATES GeneratedHeaders)
  endif()

  # Here we now have:
  #  RequiredHeaders: flat list of all of the headers from the library we are currently wrapping and
  #                   all of the libraries that it depends on

  # Export the required headers variable up to the next level so that further SWIG targets can look it up
  #set(exportname "${NAME}RequiredHeaders")

  # Oh, and also export it to this level, for peers, like the Utilities breakouts and the Model breakouts
  set(${exportname} "${RequiredHeaders}")
  set(${exportname} "${RequiredHeaders}" PARENT_SCOPE)

  if(NOT TARGET ${PARENT_TARGET}_GeneratedHeaders)
    # Add a command to generate the generated headers discovered at this point.
    add_custom_command(
      OUTPUT "${CMAKE_BINARY_DIR}/${PARENT_TARGET}_HeadersGenerated_done.stamp"
      COMMAND ${CMAKE_COMMAND} -E touch "${CMAKE_BINARY_DIR}/${PARENT_TARGET}_HeadersGenerated_done.stamp"
      DEPENDS ${GeneratedHeaders}
    )

    # And a target that calls the above command
    add_custom_target(${PARENT_TARGET}_GeneratedHeaders
      SOURCES "${CMAKE_BINARY_DIR}/${PARENT_TARGET}_HeadersGenerated_done.stamp"
    )

    # Now we say that our PARENT_TARGET depends on this new GeneratedHeaders
    # target. This is where the magic happens. By making both the parent
    # and this *_swig.cxx files below rely on this new target we force all
    # of the generated files to be generated before either the
    # PARENT_TARGET is built or the cxx files are generated. This solves the problems with
    # parallel builds trying to generate the same file multiple times while still
    # allowing files to compile in parallel
    add_dependencies(${PARENT_TARGET} ${PARENT_TARGET}_GeneratedHeaders)
  endif()

  ##
  ## Finish requirements gathering
  ##





  include_directories(${RUBY_INCLUDE_DIRS})

  if(WIN32)
    set(SWIG_DEFINES "-D_WINDOWS")
    set(SWIG_COMMON "-Fmicrosoft")
  endif()

  # Ruby bindings

  # check if this is the OpenStudioUtilities project
  string(REGEX MATCH "OpenStudioUtilities" IS_UTILTIES "${NAME}")

  set(swig_target "ruby_${NAME}")

  # wrapper file output
  set(SWIG_WRAPPER "ruby_${NAME}_wrap.cxx")
  set(SWIG_WRAPPER_FULL_PATH "${CMAKE_CURRENT_BINARY_DIR}/${SWIG_WRAPPER}")
  # ruby dlls should be all lowercase
  string(TOLOWER "${NAME}" LOWER_NAME)

  # utilities goes into OpenStudio:: directly, everything else is nested
  if(IS_UTILTIES)
    set(MODULE "OpenStudio")
  else()
    set(MODULE "OpenStudio::${SIMPLENAME}")
  endif()

  if(DEFINED OpenStudioCore_SWIG_INCLUDE_DIR)
    set(extra_includes "-I${OpenStudioCore_SWIG_INCLUDE_DIR}")
  endif()

  if(DEFINED OpenStudioCore_DIR)
    set(extra_includes2 "-I${OpenStudioCore_DIR}/src")
  endif()

  set(this_depends ${ParentSWIGWrappers})
  list(APPEND this_depends ${PARENT_TARGET}_GeneratedHeaders)
  list(APPEND this_depends ${RequiredHeaders})
  list(REMOVE_DUPLICATES this_depends)
  set(${NAME}_SWIG_Depends "${this_depends}")
  set(${NAME}_SWIG_Depends "${this_depends}" PARENT_SCOPE)

  #message(STATUS "${${NAME}_SWIG_Depends}")

  add_custom_command(
    OUTPUT "${SWIG_WRAPPER}"
    COMMAND "${SWIG_EXECUTABLE}"
            "-ruby" "-c++" "-fvirtual" "-I${CMAKE_SOURCE_DIR}/src" "-I${CMAKE_BINARY_DIR}/src" "${extra_includes}" "${extra_includes2}"
            -features autodoc=1
            -module "${MODULE}" -initname "${LOWER_NAME}"
            -o "${SWIG_WRAPPER_FULL_PATH}"
            "${SWIG_DEFINES}" ${SWIG_COMMON} "${KEY_I_FILE}"
    DEPENDS ${this_depends}
  )


  add_library(
    ${swig_target}
    MODULE
    ${SWIG_WRAPPER}
  )


  AddPCH(${swig_target})

  # run rdoc
  if(BUILD_DOCUMENTATION)
    add_custom_target(${swig_target}_rdoc
      ${CMAKE_COMMAND} -E chdir "${CMAKE_BINARY_DIR}/ruby/${CMAKE_CFG_INTDIR}" "${RUBY_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/../developer/ruby/SwigWrapToRDoc.rb" "${CMAKE_BINARY_DIR}/ruby/${CMAKE_CFG_INTDIR}/" "${SWIG_WRAPPER_FULL_PATH}" "${NAME}"
      DEPENDS ${SWIG_WRAPPER}
    )

    # Add this documentation target to the list of all targets
    list(APPEND ALL_RDOC_TARGETS ${swig_target}_rdoc)
    set(ALL_RDOC_TARGETS "${ALL_RDOC_TARGETS}" PARENT_SCOPE)

  endif()

  set_target_properties(${swig_target} PROPERTIES PREFIX "")
  set_target_properties(${swig_target} PROPERTIES OUTPUT_NAME "${LOWER_NAME}")
  if(APPLE)
    set_target_properties(${swig_target} PROPERTIES SUFFIX ".bundle" )
    #set_target_properties(${swig_target} PROPERTIES LINK_FLAGS "-undefined dynamic_lookup")
    #set_target_properties(${swig_target} PROPERTIES LINK_FLAGS "-undefined suppress -flat_namespace")
  endif()


  if(MSVC)
    # if visual studio 2010 or greater
    if(NOT (${MSVC_VERSION} LESS 1600))
      # trouble with macro redefinition in win32.h of Ruby
      set_target_properties(${swig_target} PROPERTIES COMPILE_FLAGS "/bigobj /wd4005 /wd4996") ## /wd4996 suppresses deprecated warning
    else()
      set_target_properties(${swig_target} PROPERTIES COMPILE_FLAGS "/bigobj /wd4996") ## /wd4996 suppresses deprecated warning
    endif()
  elseif(UNIX)
    if(APPLE AND NOT CMAKE_COMPILER_IS_GNUCXX)
      set_target_properties(${swig_target} PROPERTIES COMPILE_FLAGS "-Wno-dynamic-class-memaccess -Wno-deprecated-declarations")
    else()
      set_target_properties(${swig_target} PROPERTIES COMPILE_FLAGS "-Wno-deprecated-declarations")
    endif()
  endif()

  if(CMAKE_COMPILER_IS_GNUCXX)
    if(GCC_VERSION VERSION_GREATER 4.6 OR GCC_VERSION VERSION_EQUAL 4.6)
      set_source_files_properties(${SWIG_WRAPPER} PROPERTIES COMPILE_FLAGS "-Wno-uninitialized -Wno-unused-but-set-variable")
    else()
      set_source_files_properties(${SWIG_WRAPPER} PROPERTIES COMPILE_FLAGS "-Wno-uninitialized")
    endif()
  endif()

  set_target_properties(${swig_target} PROPERTIES ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/ruby/")
  if(RUBY_VERSION_MAJOR EQUAL "2" AND MSVC)
    # Ruby 2 requires modules to have a .so extension, even on windows
    set_target_properties(${swig_target} PROPERTIES SUFFIX ".so")
  endif()
  set_target_properties(${swig_target} PROPERTIES LIBRARY_OUTPUT_DIRECTORY "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/ruby/")
  set_target_properties(${swig_target} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/ruby/")
  target_link_libraries(${swig_target} ${PARENT_TARGET} ${DEPENDS} ${RUBY_LIBRARY})

  if(APPLE)
    set(_NAME "${LOWER_NAME}.bundle")
  elseif(RUBY_VERSION_MAJOR EQUAL "2" AND MSVC)
    set(_NAME "${LOWER_NAME}.so")
  else()
    set(_NAME "${LOWER_NAME}${CMAKE_SHARED_LIBRARY_SUFFIX}")
  endif()

  if(WIN32 OR APPLE)
    install(TARGETS ${swig_target} DESTINATION Ruby/openstudio/)

    set(Prereq_Dirs
      "${CMAKE_BINARY_DIR}/Products/"
      "${CMAKE_BINARY_DIR}/Products/Release"
      "${CMAKE_BINARY_DIR}/Products/Debug"
    )

    install(CODE "
      #message(\"INSTALLING SWIG_TARGET: ${swig_target}  with NAME = ${_NAME}\")
      include(GetPrerequisites)
      get_prerequisites(\${CMAKE_INSTALL_PREFIX}/Ruby/openstudio/${_NAME} PREREQUISITES 1 1 \"\" \"${Prereq_Dirs}\")
      #message(\"PREREQUISITES = \${PREREQUISITES}\")


      if(WIN32)
        list(REVERSE PREREQUISITES)
      endif()

      foreach(PREREQ IN LISTS PREREQUISITES)
        gp_resolve_item(\"\" \${PREREQ} \"\" \"${LIBRARY_SEARCH_DIRECTORY}\" resolved_item_var)
        execute_process(COMMAND \"${CMAKE_COMMAND}\" -E copy \"\${resolved_item_var}\" \"\${CMAKE_INSTALL_PREFIX}/Ruby/openstudio/\")

        get_filename_component(PREREQNAME \${resolved_item_var} NAME)

        if(APPLE)
          execute_process(COMMAND \"install_name_tool\" -change \"\${PREREQ}\" \"@loader_path/\${PREREQNAME}\" \"\${CMAKE_INSTALL_PREFIX}/Ruby/openstudio/${_NAME}\")
          foreach(PR IN LISTS PREREQUISITES)
           gp_resolve_item(\"\" \${PR} \"\" \"\" PRPATH)
           get_filename_component( PRNAME \${PRPATH} NAME)
           execute_process(COMMAND \"install_name_tool\" -change \"\${PR}\" \"@loader_path/\${PRNAME}\" \"\${CMAKE_INSTALL_PREFIX}/Ruby/openstudio/\${PREREQNAME}\")
          endforeach()
        else()
          if(EXISTS \"\${CMAKE_INSTALL_PREFIX}/Ruby/openstudio/thirdparty.rb\")
            file(READ \"\${CMAKE_INSTALL_PREFIX}/Ruby/openstudio/thirdparty.rb\" TEXT)
          else()
            set(TEXT \"\")
          endif()
          string(REGEX MATCH \${PREREQNAME} MATCHVAR \"\${TEXT}\")
          if(NOT (\"\${MATCHVAR}\" STREQUAL \"\${PREREQNAME}\"))
            file(APPEND \"\${CMAKE_INSTALL_PREFIX}/Ruby/openstudio/thirdparty.rb\" \"DL::dlopen \\\"\\\#{File.dirname(__FILE__)}/\${PREREQNAME}\\\"\n\")
          endif()
        endif()
      endforeach()
    ")
  else()
    install(TARGETS ${swig_target} DESTINATION "${RUBY_MODULE_ARCH_DIR}")
  endif()
  if(UNIX)
    # do not write file on unix, existence of file is checked before it is loaded
    #install(CODE "
    #  file(WRITE \"\${CMAKE_INSTALL_PREFIX}/Ruby/openstudio/thirdparty.rb\" \"# Nothing to see here\")
    #")
  endif()

  execute_process(COMMAND \"${CMAKE_COMMAND}\" -E copy \"\${resolved_item_var}\" \"\${CMAKE_INSTALL_PREFIX}/Ruby/openstudio/\")

  # add this target to a "global" variable so ruby tests can require these
  list(APPEND ALL_RUBY_BINDING_TARGETS "${swig_target}")
  set(ALL_RUBY_BINDING_TARGETS "${ALL_RUBY_BINDING_TARGETS}" PARENT_SCOPE)

  # Doesn't look like this is used
  # add this target to a "global" variable so ruby tests can require these
  #list(APPEND ALL_RDOCIFY_FILES "${SWIG_WRAPPER}")
  #set(ALL_RDOCIFY_FILES "${ALL_RDOCIFY_FILES}" PARENT_SCOPE)

  # add this target to a "global" variable so ruby tests can require these
  list(APPEND ALL_RUBY_BINDING_WRAPPERS "${SWIG_WRAPPER}")
  set(ALL_RUBY_BINDING_WRAPPERS "${ALL_RUBY_BINDING_WRAPPERS}" PARENT_SCOPE)

  # add this target to a "global" variable so ruby tests can require these
  list(APPEND ALL_RUBY_BINDING_WRAPPERS_FULL_PATH "${SWIG_WRAPPER_FULL_PATH}")
  set(ALL_RUBY_BINDING_WRAPPERS_FULL_PATH "${ALL_RUBY_BINDING_WRAPPERS_FULL_PATH}" PARENT_SCOPE)

  # Python bindings
  if(PYTHON_LIBRARY AND BUILD_PYTHON_BINDINGS)
    set(swig_target "python_${NAME}")

    # utilities goes into OpenStudio. directly, everything else is nested
    # DLM: SWIG generates a file ${MODULE}.py for each module, however we have several libraries in the same module
    # so these clobber each other.  Making these unique, e.g. MODULE = TOLOWER "${NAME}", generates unique .py wrappers
    # but the module names are unknown and the bindings fail to load.  I think we need to write our own custom OpenStudio.py
    # wrapper that imports all of the libraries/python wrappers into the appropriate modules.
    # http://docs.python.org/2/tutorial/modules.html
    # http://docs.python.org/2/library/imp.html

    set(MODULE ${LOWER_NAME})

    add_custom_command(
      OUTPUT "python_${NAME}_wrap.cxx"
      COMMAND "${SWIG_EXECUTABLE}"
               "-python" "-c++"
               -features autodoc=1
               -outdir ${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/python "-I${CMAKE_SOURCE_DIR}/src" "-I${CMAKE_BINARY_DIR}/src"
               -module "${MODULE}"
               -o "${CMAKE_CURRENT_BINARY_DIR}/python_${NAME}_wrap.cxx"
               "${SWIG_DEFINES}" ${SWIG_COMMON} ${KEY_I_FILE}
      DEPENDS ${this_depends}
    )

    add_library(
      ${swig_target}
      MODULE
      python_${NAME}_wrap.cxx
    )

    set_target_properties(${swig_target} PROPERTIES OUTPUT_NAME _${LOWER_NAME})
    set_target_properties(${swig_target} PROPERTIES PREFIX "")
    set_target_properties(${swig_target} PROPERTIES ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/python/")
    set_target_properties(${swig_target} PROPERTIES LIBRARY_OUTPUT_DIRECTORY "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/python/")
    set_target_properties(${swig_target} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/python/")
    if(MSVC)
      set_target_properties(${swig_target} PROPERTIES COMPILE_FLAGS "/bigobj /wd4996") ## /wd4996 suppresses deprecated warning
      set_target_properties(${swig_target} PROPERTIES SUFFIX ".pyd")
    elseif(UNIX)
      if(APPLE AND NOT CMAKE_COMPILER_IS_GNUCXX)
        set_target_properties(${swig_target} PROPERTIES COMPILE_FLAGS "-Wno-dynamic-class-memaccess -Wno-deprecated-declarations")
      else()
        set_target_properties(${swig_target} PROPERTIES COMPILE_FLAGS "-Wno-deprecated-declarations")
      endif()
    endif()

    target_link_libraries(${swig_target} ${PARENT_TARGET} ${DEPENDS} ${PYTHON_LIBRARY})

    add_dependencies("${swig_target}" "${PARENT_TARGET}_resources")

    if(MSVC)
      set(_NAME "_${LOWER_NAME}.pyd")
    else()
      set(_NAME "_${LOWER_NAME}.so")
    endif()

    if(WIN32 OR APPLE)
      install(TARGETS ${swig_target} DESTINATION Python/openstudio/)

      set(Prereq_Dirs
        "${CMAKE_BINARY_DIR}/Products/"
        "${CMAKE_BINARY_DIR}/Products/Release"
        "${CMAKE_BINARY_DIR}/Products/Debug"
      )

      install(CODE "
        include(GetPrerequisites)
        get_prerequisites(\${CMAKE_INSTALL_PREFIX}/Python/openstudio/${_NAME} PREREQUISITES 1 1 \"\" \"${Prereq_Dirs}\")

        if(WIN32)
          list(REVERSE PREREQUISITES)
        endif()

        foreach(PREREQ IN LISTS PREREQUISITES)
          gp_resolve_item( \"\" \${PREREQ} \"\" \"${LIBRARY_SEARCH_DIRECTORY}\" resolved_item_var)
         execute_process(COMMAND \"${CMAKE_COMMAND}\" -E copy \"\${resolved_item_var}\" \"\${CMAKE_INSTALL_PREFIX}/Python/openstudio/\")

         get_filename_component(PREREQNAME \${resolved_item_var} NAME)

         if(APPLE)
           execute_process(COMMAND \"install_name_tool\" -change \"\${PREREQ}\" \"@loader_path/\${PREREQNAME}\" \"\${CMAKE_INSTALL_PREFIX}/Python/openstudio/${_NAME}\")
           foreach(PR IN LISTS PREREQUISITES)
             gp_resolve_item(\"\" \${PR} \"\" \"\" PRPATH)
             get_filename_component(PRNAME \${PRPATH} NAME)
             execute_process(COMMAND \"install_name_tool\" -change \"\${PR}\" \"@loader_path/\${PRNAME}\" \"\${CMAKE_INSTALL_PREFIX}/Python/openstudio/\${PREREQNAME}\")
           endforeach()
         endif()
       endforeach(PREREQ IN LISTS PREREQUISITES)

       if(APPLE)
         file(COPY \"${QT_LIBRARY_DIR}/QtGui.framework/Resources/qt_menu.nib\" 
              DESTINATION \"\${CMAKE_INSTALL_PREFIX}/Python/openstudio/Resources/\")
       endif()
      ")
    else()
      install(TARGETS ${swig_target} DESTINATION "lib/openstudio/python")
    endif()

    install(FILES ${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/python/${LOWER_NAME}.py DESTINATION Python/openstudio/)
    
    # add this target to a "global" variable so python tests can require these
    list(APPEND ALL_PYTHON_BINDING_TARGETS "${swig_target}")

    set(ALL_PYTHON_BINDING_TARGETS "${ALL_PYTHON_BINDING_TARGETS}" PARENT_SCOPE)
  endif()

  # csharp
  if(BUILD_CSHARP_BINDINGS)
    set(swig_target "csharp_${NAME}")

    if(IS_UTILTIES)
      set(NAMESPACE "OpenStudio")
      set(MODULE "${NAME}")
    else()
      #set(NAMESPACE "OpenStudio.${NAME}")
      set(NAMESPACE "OpenStudio")
      set(MODULE "${NAME}")
    endif()

    set(SWIG_WRAPPER "csharp_${NAME}_wrap.cxx")
    set(SWIG_WRAPPER_FULL_PATH "${CMAKE_CURRENT_BINARY_DIR}/${SWIG_WRAPPER}")

    set(CSHARP_OUTPUT_NAME "openstudio_${NAME}_csharp")
    set(CSHARP_GENERATED_SRC_DIR "${CMAKE_BINARY_DIR}/csharp_wrapper/generated_sources/${NAME}")
    file(MAKE_DIRECTORY ${CSHARP_GENERATED_SRC_DIR})

    add_custom_command(
      OUTPUT ${SWIG_WRAPPER}
      COMMAND "${CMAKE_COMMAND}" -E remove_directory "${CSHARP_GENERATED_SRC_DIR}"
      COMMAND "${CMAKE_COMMAND}" -E make_directory "${CSHARP_GENERATED_SRC_DIR}"
      COMMAND "${SWIG_EXECUTABLE}"
              "-csharp" "-c++" -namespace ${NAMESPACE}
              -features autodoc=1
              -outdir "${CSHARP_GENERATED_SRC_DIR}"  "-I${CMAKE_SOURCE_DIR}/src" "-I${CMAKE_BINARY_DIR}/src"
              -module "${MODULE}"
              -o "${SWIG_WRAPPER_FULL_PATH}"
              -dllimport "${CSHARP_OUTPUT_NAME}"
              "${SWIG_DEFINES}" ${SWIG_COMMON} ${KEY_I_FILE}
      DEPENDS ${this_depends}

    )

    add_library(
      ${swig_target}
      MODULE
      ${SWIG_WRAPPER}
    )

    set_target_properties(${swig_target} PROPERTIES OUTPUT_NAME "${CSHARP_OUTPUT_NAME}")
    set_target_properties(${swig_target} PROPERTIES PREFIX "")
    set_target_properties(${swig_target} PROPERTIES ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/csharp/")
    set_target_properties(${swig_target} PROPERTIES LIBRARY_OUTPUT_DIRECTORY "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/csharp/")
    set_target_properties(${swig_target} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/csharp/")
    if(MSVC)
      set_target_properties(${swig_target} PROPERTIES COMPILE_FLAGS "/bigobj /wd4996")  ## /wd4996 suppresses deprecated warnings
    endif()
    target_link_libraries(${swig_target} ${PARENT_TARGET} ${DEPENDS})

    #ADD_DEPENDENCIES("${swig_target}" "${PARENT_TARGET}_resources")

    # add this target to a "global" variable so csharp tests can require these
    list(APPEND ALL_CSHARP_BINDING_TARGETS "${swig_target}")
    set(ALL_CSHARP_BINDING_TARGETS "${ALL_CSHARP_BINDING_TARGETS}" PARENT_SCOPE)



    if(WIN32)
      install(TARGETS ${swig_target} DESTINATION CSharp/openstudio/)

      install(CODE "
        include(GetPrerequisites)
        get_prerequisites(\${CMAKE_INSTALL_PREFIX}/CSharp/openstudio/openstudio_${NAME}_csharp.dll PREREQUISITES 1 1 \"\" \"${CMAKE_BINARY_DIR}/Products/\")

        if(WIN32)
          list(REVERSE PREREQUISITES)
        endif()

        foreach(PREREQ IN LISTS PREREQUISITES)
          gp_resolve_item(\"\" \${PREREQ} \"\" \"${LIBRARY_SEARCH_DIRECTORY}\" resolved_item_var)
          execute_process(COMMAND \"${CMAKE_COMMAND}\" -E copy \"\${resolved_item_var}\" \"\${CMAKE_INSTALL_PREFIX}/CSharp/openstudio/\")

          get_filename_component(PREREQNAME \${resolved_item_var} NAME)
        endforeach()
      ")
    endif()
  endif()

  # java
  if(BUILD_JAVA_BINDINGS)
    set(swig_target "java_${NAME}")

    string(SUBSTRING ${NAME} 10 -1 SIMPLIFIED_NAME)
    string(TOLOWER ${SIMPLIFIED_NAME} SIMPLIFIED_NAME)

    if(IS_UTILTIES)
      set(NAMESPACE "gov.nrel.openstudio")
      set(MODULE "${SIMPLIFIED_NAME}_global")
    else()
      #set( NAMESPACE "OpenStudio.${NAME}")
      set( NAMESPACE "gov.nrel.openstudio")
      set( MODULE "${SIMPLIFIED_NAME}_global")
    endif()

    set(SWIG_WRAPPER "java_${NAME}_wrap.cxx")
    set(SWIG_WRAPPER_FULL_PATH "${CMAKE_CURRENT_BINARY_DIR}/${SWIG_WRAPPER}")

    set(JAVA_OUTPUT_NAME "${NAME}_java")
    set(JAVA_GENERATED_SRC_DIR "${CMAKE_BINARY_DIR}/java_wrapper/generated_sources/${NAME}")
    file(MAKE_DIRECTORY ${JAVA_GENERATED_SRC_DIR})

    add_custom_command(
      OUTPUT ${SWIG_WRAPPER}
      COMMAND "${CMAKE_COMMAND}" -E remove_directory "${JAVA_GENERATED_SRC_DIR}"
      COMMAND "${CMAKE_COMMAND}" -E make_directory "${JAVA_GENERATED_SRC_DIR}"
      COMMAND "${SWIG_EXECUTABLE}"
              "-java" "-c++"
              -package ${NAMESPACE}
              #-features autodoc=1
              -outdir "${JAVA_GENERATED_SRC_DIR}"  "-I${CMAKE_SOURCE_DIR}/src" "-I${CMAKE_BINARY_DIR}/src"
              -module "${MODULE}"
              -o "${SWIG_WRAPPER_FULL_PATH}"
              #-dllimport "${JAVA_OUTPUT_NAME}"
              "${SWIG_DEFINES}" ${SWIG_COMMON} ${KEY_I_FILE}
      DEPENDS ${this_depends}

    )

    include_directories("${JAVA_INCLUDE_PATH}" "${JAVA_INCLUDE_PATH2}")

    add_library(
      ${swig_target}
      MODULE
      ${SWIG_WRAPPER}
    )

    set_target_properties(${swig_target} PROPERTIES OUTPUT_NAME "${JAVA_OUTPUT_NAME}")
    #set_target_properties(${swig_target} PROPERTIES PREFIX "")
    set_target_properties(${swig_target} PROPERTIES ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/java/")
    set_target_properties(${swig_target} PROPERTIES LIBRARY_OUTPUT_DIRECTORY "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/java/")
    set_target_properties(${swig_target} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/java/")
    if(MSVC)
      set_target_properties(${swig_target} PROPERTIES COMPILE_FLAGS "/bigobj /wd4996") ## /wd4996 suppresses deprecated warnings
      set(final_name "${JAVA_OUTPUT_NAME}.dll")
    elseif(UNIX)
      set_target_properties(${swig_target} PROPERTIES COMPILE_FLAGS "-Wno-deprecated-declarations")
    endif()

    target_link_libraries(${swig_target} ${PARENT_TARGET} ${DEPENDS} ${JAVA_JVM_LIBRARY})
    if(APPLE)
      set_target_properties(${swig_target} PROPERTIES SUFFIX ".dylib")
      set(final_name "lib${JAVA_OUTPUT_NAME}.dylib")
    endif()

    #add_dependencies("${swig_target}" "${PARENT_TARGET}_resources")

    # add this target to a "global" variable so java tests can require these
    list(APPEND ALL_JAVA_BINDING_TARGETS "${swig_target}")
    set(ALL_JAVA_BINDING_TARGETS "${ALL_JAVA_BINDING_TARGETS}" PARENT_SCOPE)

    list(APPEND ALL_JAVA_SRC_DIRECTORIES "${JAVA_GENERATED_SRC_DIR}")
    set(ALL_JAVA_SRC_DIRECTORIES "${ALL_JAVA_SRC_DIRECTORIES}" PARENT_SCOPE)


    if(WIN32 OR APPLE)
      install(TARGETS ${swig_target} DESTINATION Java/openstudio/)

      install(CODE "
        include(GetPrerequisites)
        get_prerequisites(\${CMAKE_INSTALL_PREFIX}/Java/openstudio/${final_name} PREREQUISITES 1 1 \"\" \"${CMAKE_BINARY_DIR}/Products/\")

        if(WIN32)
          list(REVERSE PREREQUISITES)
        endif()

        foreach(PREREQ IN LISTS PREREQUISITES)
          gp_resolve_item(\"\" \${PREREQ} \"\" \"${LIBRARY_SEARCH_DIRECTORY}\" resolved_item_var)
          execute_process(COMMAND \"${CMAKE_COMMAND}\" -E copy \"\${resolved_item_var}\" \"\${CMAKE_INSTALL_PREFIX}/Java/openstudio/\")

          get_filename_component(PREREQNAME \${resolved_item_var} NAME)

          if(APPLE)
            execute_process(COMMAND \"install_name_tool\" -change \"\${PREREQ}\" \"@loader_path/\${PREREQNAME}\" \"\${CMAKE_INSTALL_PREFIX}/Java/openstudio/${final_name}\")
            foreach(PR IN LISTS PREREQUISITES)
              gp_resolve_item(\"\" \${PR} \"\" \"\" PRPATH)
              get_filename_component(PRNAME \${PRPATH} NAME)
              execute_process(COMMAND \"install_name_tool\" -change \"\${PR}\" \"@loader_path/\${PRNAME}\" \"\${CMAKE_INSTALL_PREFIX}/Java/openstudio/\${PREREQNAME}\")
            endforeach()
          endif()
        endforeach()
      ")
    else()
      install(TARGETS ${swig_target} DESTINATION "lib/openstudio-${OPENSTUDIO_VERSION}/java")
    endif()
  endif()


  # v8
  if(BUILD_V8_BINDINGS)
    set(swig_target "v8_${NAME}")

    if(IS_UTILTIES)
      set(NAMESPACE "OpenStudio")
      set(MODULE "${NAME}")
    else()
      #set(NAMESPACE "OpenStudio.${NAME}")
      set(NAMESPACE "OpenStudio")
      set(MODULE "${NAME}")
    endif()

    set(SWIG_WRAPPER "v8_${NAME}_wrap.cxx")
    set(SWIG_WRAPPER_FULL_PATH "${CMAKE_CURRENT_BINARY_DIR}/${SWIG_WRAPPER}")

    set(v8_OUTPUT_NAME "${NAME}")
    #set(CSHARP_GENERATED_SRC_DIR "${CMAKE_BINARY_DIR}/csharp_wrapper/generated_sources/${NAME}")
    #file(MAKE_DIRECTORY ${CSHARP_GENERATED_SRC_DIR})

    if(BUILD_NODE_MODULES)
      set(V8_DEFINES "-DBUILD_NODE_MODULE")
      set(SWIG_ENGINE "-node")
    else()
      set(V8_DEFINES "")
      set(SWIG_ENGINE "-v8")
    endif()

    add_custom_command(
      OUTPUT ${SWIG_WRAPPER}
      COMMAND "${SWIG_EXECUTABLE}"
              "-javascript" ${SWIG_ENGINE} "-c++"
              #-namespace ${NAMESPACE}
              #-features autodoc=1
              #-outdir "${CSHARP_GENERATED_SRC_DIR}"
              "-I${CMAKE_SOURCE_DIR}/src" "-I${CMAKE_BINARY_DIR}/src"
              -module "${MODULE}"
              -o "${SWIG_WRAPPER_FULL_PATH}"
              "${SWIG_DEFINES}" ${V8_DEFINES} ${SWIG_COMMON} ${KEY_I_FILE}
              DEPENDS ${this_depends}

    )

    if(BUILD_NODE_MODULES)
      include_directories("${NODE_INCLUDE_DIR}" "${NODE_INCLUDE_DIR}/deps/v8/include" "${NODE_INCLUDE_DIR}/deps/uv/include" "${NODE_INCLUDE_DIR}/src")
    else()
      include_directories(${V8_INCLUDE_DIR})
    endif()

    add_library(
      ${swig_target}
      MODULE
      ${SWIG_WRAPPER}
    )

    set_target_properties(${swig_target} PROPERTIES OUTPUT_NAME ${v8_OUTPUT_NAME})
    set_target_properties(${swig_target} PROPERTIES PREFIX "")
    set(_NAME "${v8_OUTPUT_NAME}.node")
    if(BUILD_NODE_MODULES)
      set_target_properties(${swig_target} PROPERTIES SUFFIX ".node")
    endif()
    set_target_properties(${swig_target} PROPERTIES ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/v8/")
    set_target_properties(${swig_target} PROPERTIES LIBRARY_OUTPUT_DIRECTORY "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/v8/")
    set_target_properties(${swig_target} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/v8/")

    if(MSVC)
      set_target_properties(${swig_target} PROPERTIES COMPILE_FLAGS "/bigobj /DBUILDING_NODE_EXTENSION /wd4996")  ## /wd4996 suppresses deprecated warnings
    elseif(UNIX)
      set_target_properties(${swig_target} PROPERTIES COMPILE_FLAGS "-DBUILDING_NODE_EXTENSION -Wno-deprecated-declarations")
    endif()

    if(APPLE)
      set_target_properties(${swig_target} PROPERTIES LINK_FLAGS "-undefined suppress -flat_namespace")
    endif()
    target_link_libraries(${swig_target} ${PARENT_TARGET} ${DEPENDS})

    #add_dependencies("${swig_target}" "${PARENT_TARGET}_resources")

    # add this target to a "global" variable so v8 tests can require these
    list(APPEND ALL_V8_BINDING_TARGETS "${swig_target}")
    set(ALL_V8_BINDING_TARGETS "${ALL_V8_BINDING_TARGETS}" PARENT_SCOPE)

    if(BUILD_NODE_MODULES)
      set(V8_TYPE "node")
    else()
      set(V8_TYPE "v8")
    endif()

    if(WIN32 OR APPLE)
      install(TARGETS ${swig_target} DESTINATION "${V8_TYPE}/openstudio/")

      set(Prereq_Dirs
        "${CMAKE_BINARY_DIR}/Products/"
        "${CMAKE_BINARY_DIR}/Products/Release"
        "${CMAKE_BINARY_DIR}/Products/Debug"
      )

      install(CODE "
        #message(\"INSTALLING SWIG_TARGET: ${swig_target}  with NAME = ${_NAME}\")
        include(GetPrerequisites)
        get_prerequisites(\${CMAKE_INSTALL_PREFIX}/${V8_TYPE}/openstudio/${_NAME} PREREQUISITES 1 1 \"\" \"${Prereq_Dirs}\")
        #message(\"PREREQUISITES = \${PREREQUISITES}\")


        if(WIN32)
          list(REVERSE PREREQUISITES)
        endif()

        foreach(PREREQ IN LISTS PREREQUISITES)
          gp_resolve_item(\"\" \${PREREQ} \"\" \"${LIBRARY_SEARCH_DIRECTORY}\" resolved_item_var)
          #message(\"prereq = ${PREREQ}  resolved = ${resolved_item_var} \")
          execute_process(COMMAND \"${CMAKE_COMMAND}\" -E copy \"\${resolved_item_var}\" \"\${CMAKE_INSTALL_PREFIX}/${V8_TYPE}/openstudio/\")

          get_filename_component(PREREQNAME \${resolved_item_var} NAME)

          if(APPLE)
            execute_process(COMMAND \"install_name_tool\" -change \"\${PREREQ}\" \"@loader_path/\${PREREQNAME}\" \"\${CMAKE_INSTALL_PREFIX}/${V8_TYPE}/openstudio/${_NAME}\")
            foreach(PR IN LISTS PREREQUISITES)
              gp_resolve_item(\"\" \${PR} \"\" \"\" PRPATH)
              get_filename_component(PRNAME \${PRPATH} NAME)
              execute_process(COMMAND \"install_name_tool\" -change \"\${PR}\" \"@loader_path/\${PRNAME}\" \"\${CMAKE_INSTALL_PREFIX}/${V8_TYPE}/openstudio/\${PREREQNAME}\")
            endforeach()
          endif()
        endforeach()
        if(APPLE)
          file(COPY \"${QT_LIBRARY_DIR}/QtGui.framework/Resources/qt_menu.nib\"
            DESTINATION \"\${CMAKE_INSTALL_PREFIX}/${V8_TYPE}/openstudio/Resources/\"
          )
        endif()
      ")
    else()
      install(TARGETS ${swig_target} DESTINATION "lib/openstudio-${OPENSTUDIO_VERSION}/${V8_TYPE}")
    endif()
  endif()


endmacro()

# add target dependencies
# this will add targets to a "global" variable marking
# them to have their dependencies installed later.
macro(ADD_DEPENDENCIES_FOR_TARGET target)
  get_target_property(target_path ${target} LOCATION_DEBUG)
  list(APPEND DEPENDENCY_TARGETS ${target_path})
  set(DEPENDENCY_TARGETS "${DEPENDENCY_TARGETS}" PARENT_SCOPE)
endmacro()

# install target dependencies
# this will actually install the dependencies of the marked targets
# this is called after all targets have been defined.  Dependencies are
# found for all targets and the duplicates are removed so to not try to
# install twice.
macro(INSTALL_RUNTIME_DPENDENCIES targets)
  set(install_code "
    include(GetPrerequisites)
    foreach(target \"${targets}\")
      get_prerequisites( \"\${target}\" DEPENDS 1 0 \"\" \"\")
      foreach(DEPEND \${DEPENDS})
        set(DEPEND_FULL_PATH \"DEPEND_FULL_PATH-NOTFOUND\")
        find_program(DEPEND_FULL_PATH \"\${DEPEND}\")
        list(APPEND DEPEND_FULL_PATHS \"\${DEPEND_FULL_PATH}\")
      endforeach()
    endforeach()
    list(REMOVE_DUPLICATES DEPEND_FULL_PATHS)
    file(INSTALL DESTINATION \"\${CMAKE_INSTALL_PREFIX}/bin\"
      TYPE EXECUTABLE
      FILES \${DEPEND_FULL_PATHS}
    )
  ")
  install(CODE "${install_code}")
endmacro()


# run energyplus
# appends output (eplusout.err) to list ENERGYPLUS_OUTPUTS
macro(RUN_ENERGYPLUS FILENAME DIRECTORY WEATHERFILE)
  list(APPEND ENERGYPLUS_OUTPUTS "${DIRECTORY}/eplusout.err")
  add_custom_command(
    OUTPUT "${DIRECTORY}/eplusout.err"
    COMMAND ${CMAKE_COMMAND} -E copy "${DIRECTORY}/${FILENAME}" "${DIRECTORY}/in.idf"
    COMMAND ${CMAKE_COMMAND} -E copy "${ENERGYPLUS_IDD}" "${DIRECTORY}/Energy+.idd"
    COMMAND ${CMAKE_COMMAND} -E copy "${ENERGYPLUS_WEATHER_DIR}/${WEATHERFILE}" "${DIRECTORY}/in.epw"
    COMMAND ${CMAKE_COMMAND} -E chdir "${DIRECTORY}" "${ENERGYPLUS_EXE}" ">" "${DIRECTORY}/screen.out"
    DEPENDS "${ENERGYPLUS_IDD}" "${ENERGYPLUS_WEATHER_DIR}/${WEATHERFILE}" "${ENERGYPLUS_EXE}" "${CMAKE_CURRENT_BINARY_DIR}/${DIRECTORY}/${FILENAME}"
    COMMENT "Updating EnergyPlus simulation in ${CMAKE_CURRENT_BINARY_DIR}/${DIRECTORY}/, this may take a while"
  )
endmacro()

# run energyplus
# appends output (eplusout.err) to list ENERGYPLUS_OUTPUTS
macro(RUN_ENERGYPLUS_CUSTOMEPW FILENAMEANDPATH WEATHERFILENAMEANDPATH RUN_DIRECTORY)
  list(APPEND ENERGYPLUS_OUTPUTS "${RUN_DIRECTORY}/eplusout.err")
  add_custom_command(
    OUTPUT "${RUN_DIRECTORY}/eplusout.err"
    COMMAND ${CMAKE_COMMAND} -E copy "${FILENAMEANDPATH}" "${RUN_DIRECTORY}/in.idf"
    COMMAND ${CMAKE_COMMAND} -E copy "${ENERGYPLUS_IDD}" "${RUN_DIRECTORY}/Energy+.idd"
    COMMAND ${CMAKE_COMMAND} -E copy "${WEATHERFILENAMEANDPATH}" "${RUN_DIRECTORY}/in.epw"
    COMMAND ${CMAKE_COMMAND} -E chdir "${RUN_DIRECTORY}" "${ENERGYPLUS_EXE}" ">" "${RUN_DIRECTORY}/screen.out"
    DEPENDS "${ENERGYPLUS_IDD}" "${CMAKE_CURRENT_BINARY_DIR}/${WEATHERFILENAMEANDPATH}" "${ENERGYPLUS_EXE}" "${CMAKE_CURRENT_BINARY_DIR}/${FILENAMEANDPATH}"
    COMMENT "Updating EnergyPlus simulation in ${CMAKE_CURRENT_BINARY_DIR}/${RUN_DIRECTORY}/, this may take a while"
  )
endmacro()

# adds custom command to update a resource
macro(UPDATE_RESOURCES SRCS)
  foreach(SRC ${SRCS})
    add_custom_command(
      OUTPUT "${SRC}"
      COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_CURRENT_SOURCE_DIR}/${SRC}" "${SRC}"
      DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/${SRC}"
    )
  endforeach()
endmacro()

# adds custom command to update a resource via configure
macro(CONFIGURE_RESOURCES SRCS)
  foreach(SRC ${SRCS})
    # Would like to wrap this up in a custom command, but no luck thus far.
    # ADD_CUSTOM_COMMAND(
    #  OUTPUT "${SRC}"
    #  DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/${SRC}"
    #  COMMAND ${CMAKE_COMMAND}
    #  ARGS -Dfile_name=${SRC} -Dinclude_name=${include_name} -E

      configure_file( "${CMAKE_CURRENT_SOURCE_DIR}/${SRC}" "${SRC}" )

    #)
  endforeach()
endmacro()


# This function is nearly identical to QT5_WRAP_CPP (from Qt5CoreMacros.cmake), except that it removes Boost
# from the include directories and outputs .cxx files

# qt5_wrap_cpp_minimally(outfiles inputfile ...)
function(QT5_WRAP_CPP_MINIMALLY outfiles)
  # Remove Boost and possibly other include directories
  get_directory_property(_inc_DIRS INCLUDE_DIRECTORIES)
  set(_orig_DIRS ${_inc_DIRS})
  if(UNIX AND NOT APPLE)
    foreach(_current ${_inc_DIRS})
      if(NOT "${_current}" MATCHES "[Qq][Tt]5")
        list(REMOVE_ITEM _inc_DIRS "${_current}")
      endif()
    endforeach()
    set_directory_properties(PROPERTIES INCLUDE_DIRECTORIES "${CMAKE_SOURCE_DIR}/src;${CMAKE_BINARY_DIR}/src;${_inc_DIRS}")
  else()
    foreach(_current ${_inc_DIRS})
      if("${_current}" MATCHES "[Bb][Oo][Oo][Ss][Tt]")
        list(REMOVE_ITEM _inc_DIRS "${_current}")
      endif()
    endforeach()
    set_directory_properties(PROPERTIES INCLUDE_DIRECTORIES "${_inc_DIRS}")
  endif()

  qt5_get_moc_flags(moc_flags)

  set(options)
  set(oneValueArgs TARGET)
  set(multiValueArgs OPTIONS)

  cmake_parse_arguments(_WRAP_CPP "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  set(moc_files ${_WRAP_CPP_UNPARSED_ARGUMENTS})
  set(moc_options ${_WRAP_CPP_OPTIONS})
  set(moc_target ${_WRAP_CPP_TARGET})

  if (moc_target AND CMAKE_VERSION VERSION_LESS 2.8.12)
    message(FATAL_ERROR "The TARGET parameter to qt5_wrap_cpp is only available when using CMake 2.8.12 or later.")
  endif()
  foreach(it ${moc_files})
    get_filename_component(it ${it} ABSOLUTE)
    qt5_make_output_file(${it} moc_ cxx outfile)
    qt5_create_moc_command(${it} ${outfile} "${moc_flags}" "${moc_options}" "${moc_target}")
    list(APPEND ${outfiles} ${outfile})
  endforeach()
  set(${outfiles} ${${outfiles}} PARENT_SCOPE)

  # Restore include directories
  set_directory_properties(PROPERTIES INCLUDE_DIRECTORIES "${_orig_DIRS}")
endfunction()
