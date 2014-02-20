/**********************************************************************
 *  Copyright (c) 2008-2013, Alliance for Sustainable Energy.  
 *  All rights reserved.
 *  
 *  This library is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU Lesser General Public
 *  License as published by the Free Software Foundation; either
 *  version 2.1 of the License, or (at your option) any later version.
 *  
 *  This library is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *  Lesser General Public License for more details.
 *  
 *  You should have received a copy of the GNU Lesser General Public
 *  License along with this library; if not, write to the Free Software
 *  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 **********************************************************************/

#ifndef OPENSTUDIO_OSCONCEPT_H
#define OPENSTUDIO_OSCONCEPT_H

#include <shared_gui_components/FieldMethodTypedefs.hpp>

#include <model/ModelObject.hpp>

namespace openstudio {

class BaseConcept
{
  public:

  virtual ~BaseConcept() {}

  BaseConcept(QString t_headingLabel)
    : m_headingLabel(t_headingLabel)
  {
  }

  QString headingLabel() const { return m_headingLabel; }

  private:

  QString m_headingLabel;

}; 


///////////////////////////////////////////////////////////////////////////////////


class CheckBoxConcept : public BaseConcept
{
  public:

   CheckBoxConcept(QString t_headingLabel)
     : BaseConcept(t_headingLabel)
  {
  }

  virtual bool get(const model::ModelObject & obj) = 0;
  virtual void set(const model::ModelObject & obj, bool) = 0;
}; 

template<typename DataSourceType>
class CheckBoxConceptImpl : public CheckBoxConcept
{
  public:

  CheckBoxConceptImpl(QString t_headingLabel, 
    boost::function<bool (DataSourceType *)>  t_getter, 
    boost::function<void (DataSourceType *, bool)> t_setter)
    : CheckBoxConcept(t_headingLabel),
      m_getter(t_getter),
      m_setter(t_setter)
  {
  }

  virtual bool get(const model::ModelObject & t_obj)
  {
    DataSourceType obj = t_obj.cast<DataSourceType>();
    return m_getter(&obj);
  }

  virtual void set(const model::ModelObject & t_obj, bool value)
  {
    DataSourceType obj = t_obj.cast<DataSourceType>();
    return m_setter(&obj, value);
  }

  private:

  boost::function<bool (DataSourceType *)>  m_getter;
  boost::function<bool (DataSourceType *, bool)> m_setter;
};


///////////////////////////////////////////////////////////////////////////////////


class ComboBoxConcept : public BaseConcept
{
  public:

   ComboBoxConcept(QString t_headingLabel)
    : BaseConcept(t_headingLabel)
  {
  }

  virtual std::vector<std::string> choices() = 0;
  virtual std::string get(const model::ModelObject & obj) = 0;
  virtual bool set(const model::ModelObject & obj, std::string) = 0;
}; 

template<typename DataSourceType>
class ComboBoxConceptImpl : public ComboBoxConcept
{
  public:

  ComboBoxConceptImpl(QString t_headingLabel, 
    boost::function<std::vector<std::string> (void)> t_choices, 
    boost::function<std::string (DataSourceType *)>  t_getter, 
    boost::function<bool (DataSourceType *, std::string)> t_setter)
    : ComboBoxConcept(t_headingLabel),
      m_choices(t_choices),
      m_getter(t_getter),
      m_setter(t_setter)
  {
  }

  virtual std::vector<std::string> choices()
  {
    return m_choices();
  }

  virtual std::string get(const model::ModelObject & t_obj)
  {
    DataSourceType obj = t_obj.cast<DataSourceType>();
    return m_getter(&obj);
  }

  virtual bool set(const model::ModelObject & t_obj, std::string value)
  {
    DataSourceType obj = t_obj.cast<DataSourceType>();
    return m_setter(&obj,value);
  }

  private:

  boost::function<std::vector<std::string> (void)> m_choices;
  boost::function<std::string (DataSourceType *)>  m_getter;
  boost::function<bool (DataSourceType *, std::string)> m_setter;
};


///////////////////////////////////////////////////////////////////////////////////


class DoubleEditConcept : public BaseConcept
{
  public:

  DoubleEditConcept(QString t_headingLabel)
    : BaseConcept(t_headingLabel)
  {
  }

  virtual double get(const model::ModelObject & obj) = 0;
  virtual bool set(const model::ModelObject & obj, double) = 0;
}; 

template<typename DataSourceType>
class DoubleEditConceptImpl : public DoubleEditConcept
{
  public:

  DoubleEditConceptImpl(QString t_headingLabel, 
    boost::function<double (DataSourceType *)>  t_getter, 
    boost::function<bool (DataSourceType *, double)> t_setter)
    : DoubleEditConcept(t_headingLabel),
      m_getter(t_getter),
      m_setter(t_setter)
  {
  }

  virtual double get(const model::ModelObject & t_obj)
  {
    DataSourceType obj = t_obj.cast<DataSourceType>();
    return m_getter(&obj);
  }

  virtual bool set(const model::ModelObject & t_obj, double value)
  {
    DataSourceType obj = t_obj.cast<DataSourceType>();
    return m_setter(&obj,value);
  }

  private:

  boost::function<double (DataSourceType *)>  m_getter;
  boost::function<bool (DataSourceType *, double)> m_setter;
};


///////////////////////////////////////////////////////////////////////////////////


class OptionalDoubleEditConcept : public BaseConcept
{
  public:

   OptionalDoubleEditConcept(QString t_headingLabel)
     : BaseConcept(t_headingLabel)
  {
  }

  virtual boost::optional<double> get(const model::ModelObject & obj) = 0;
  virtual bool set(const model::ModelObject & obj, double) = 0;
}; 

template<typename DataSourceType>
class OptionalDoubleEditConceptImpl : public OptionalDoubleEditConcept
{
  public:

  OptionalDoubleEditConceptImpl(QString t_headingLabel, 
    boost::function<boost::optional<double> (DataSourceType *)>  t_getter, 
    boost::function<bool (DataSourceType *, double)> t_setter)
    : OptionalDoubleEditConcept(t_headingLabel),
      m_getter(t_getter),
      m_setter(t_setter)
  {
  }

  virtual boost::optional<double> get(const model::ModelObject & t_obj)
  {
    DataSourceType obj = t_obj.cast<DataSourceType>();
    return m_getter(&obj);
  }

  virtual bool set(const model::ModelObject & t_obj, double value)
  {
    DataSourceType obj = t_obj.cast<DataSourceType>();
    return m_setter(&obj,value);
  }

  private:

  boost::function<boost::optional<double> (DataSourceType *)>  m_getter;
  boost::function<bool (DataSourceType *, double)> m_setter;
};


///////////////////////////////////////////////////////////////////////////////////


class DoubleEditVoidReturnConcept : public BaseConcept
{
  public:

   DoubleEditVoidReturnConcept(QString t_headingLabel)
     : BaseConcept(t_headingLabel)
  {
  }

  virtual double get(const model::ModelObject & obj) = 0;
  virtual void set(const model::ModelObject & obj, double) = 0;
}; 

template<typename DataSourceType>
class DoubleEditVoidReturnConceptImpl : public DoubleEditVoidReturnConcept
{
  public:

  DoubleEditVoidReturnConceptImpl(QString t_headingLabel,
    boost::function<double (DataSourceType *)>  t_getter,
    boost::function<void (DataSourceType *, double)> t_setter)
    : DoubleEditVoidReturnConcept(t_headingLabel),
      m_getter(t_getter),
      m_setter(t_setter)
  {
  }

  virtual double get(const model::ModelObject & t_obj)
  {
    DataSourceType obj = t_obj.cast<DataSourceType>();
    return m_getter(&obj);
  }

  virtual void set(const model::ModelObject & t_obj, double value)
  {
    DataSourceType obj = t_obj.cast<DataSourceType>();
    return m_setter(&obj,value);
  }

  private:

  boost::function<double (DataSourceType *)>  m_getter;
  boost::function<void (DataSourceType *, double)> m_setter;
};


///////////////////////////////////////////////////////////////////////////////////


class OptionalDoubleEditVoidReturnConcept : public BaseConcept
{
  public:

  OptionalDoubleEditVoidReturnConcept(QString t_headingLabel)
    : BaseConcept(t_headingLabel)
  {
  }

  virtual boost::optional<double> get(const model::ModelObject & obj) = 0;
  virtual void set(const model::ModelObject & obj, double) = 0;
}; 

template<typename DataSourceType>
class OptionalDoubleEditVoidReturnConceptImpl : public OptionalDoubleEditVoidReturnConcept
{
  public:

  OptionalDoubleEditVoidReturnConceptImpl(QString t_headingLabel, 
    boost::function<boost::optional<double> (DataSourceType *)>  t_getter, 
    boost::function<void (DataSourceType *, double)> t_setter)
    : OptionalDoubleEditVoidReturnConcept(t_headingLabel),
      m_getter(t_getter),
      m_setter(t_setter)
  {
  }

  virtual boost::optional<double> get(const model::ModelObject & t_obj)
  {
    DataSourceType obj = t_obj.cast<DataSourceType>();
    return m_getter(&obj);
  }

  virtual void set(const model::ModelObject & t_obj, double value)
  {
    DataSourceType obj = t_obj.cast<DataSourceType>();
    return m_setter(&obj,value);
  }

  private:

  boost::function<boost::optional<double> (DataSourceType *)>  m_getter;
  boost::function<void (DataSourceType *, double)> m_setter;
};


///////////////////////////////////////////////////////////////////////////////////


class IntegerEditConcept : public BaseConcept
{
  public:

  IntegerEditConcept(QString t_headingLabel)
    : BaseConcept(t_headingLabel)
  {
  }

  virtual int get(const model::ModelObject & obj) = 0;
  virtual bool set(const model::ModelObject & obj, int) = 0;
};

template<typename DataSourceType>
class IntegerEditConceptImpl : public IntegerEditConcept
{
  public:

  IntegerEditConceptImpl(QString t_headingLabel,
    boost::function<int (DataSourceType *)>  t_getter, 
    boost::function<bool (DataSourceType *, int)> t_setter)
    : IntegerEditConcept(t_headingLabel),
      m_getter(t_getter),
      m_setter(t_setter)
  {
  }

  virtual int get(const model::ModelObject & t_obj)
  {
    DataSourceType obj = t_obj.cast<DataSourceType>();
    return m_getter(&obj);
  }

  virtual bool set(const model::ModelObject & t_obj, int value)
  {
    DataSourceType obj = t_obj.cast<DataSourceType>();
    return m_setter(&obj,value);
  }

  private:

  boost::function<int (DataSourceType *)>  m_getter;
  boost::function<bool (DataSourceType *, int)> m_setter;
};


///////////////////////////////////////////////////////////////////////////////////
  

class LineEditConcept : public BaseConcept
{
  public:

  LineEditConcept(QString t_headingLabel)
    : BaseConcept(t_headingLabel)
  {
  }

  virtual std::string get(const model::ModelObject & obj) = 0;
  virtual bool set(const model::ModelObject & obj, std::string) = 0;
}; 

template<typename DataSourceType>
class LineEditConceptImpl : public LineEditConcept
{
  public:

  LineEditConceptImpl(QString t_headingLabel, 
    boost::function<std::string (DataSourceType *)>  t_getter, 
    boost::function<bool (DataSourceType *, std::string)> t_setter)
    : LineEditConcept(t_headingLabel),
      m_getter(t_getter),
      m_setter(t_setter)
  {
  }

  virtual std::string get(const model::ModelObject & t_obj)
  {
    DataSourceType obj = t_obj.cast<DataSourceType>();
    return m_getter(&obj);
  }

  virtual bool set(const model::ModelObject & t_obj, std::string value)
  {
    DataSourceType obj = t_obj.cast<DataSourceType>();
    return m_setter(&obj,value);
  }

  private:

  boost::function<std::string (DataSourceType *)>  m_getter;
  boost::function<bool (DataSourceType *, std::string)> m_setter;
};


///////////////////////////////////////////////////////////////////////////////////
  

class NameLineEditConcept : public BaseConcept
{
  public:

  NameLineEditConcept(QString t_headingLabel)
    : BaseConcept(t_headingLabel)
  {
  }

  virtual boost::optional<std::string> get(const model::ModelObject & obj, bool) = 0;
  virtual boost::optional<std::string> set(const model::ModelObject & obj, const std::string &) = 0;
}; 

template<typename DataSourceType>
class NameLineEditConceptImpl : public NameLineEditConcept
{
  public:

  NameLineEditConceptImpl(QString t_headingLabel,
    boost::function<boost::optional<std::string> (DataSourceType *, bool)>  t_getter, 
    boost::function<boost::optional<std::string> (DataSourceType *, const std::string &)> t_setter)
    : NameLineEditConcept(t_headingLabel),
      m_getter(t_getter),
      m_setter(t_setter)
  {
  }

  virtual boost::optional<std::string> get(const model::ModelObject & t_obj, bool value)
  {
    DataSourceType obj = t_obj.cast<DataSourceType>();
    return m_getter(&obj,value);
  }

  virtual boost::optional<std::string> set(const model::ModelObject & t_obj, const std::string & value)
  {
    DataSourceType obj = t_obj.cast<DataSourceType>();
    return m_setter(&obj,value);
  }

  private:

  boost::function<boost::optional<std::string> (DataSourceType *, bool)>  m_getter;
  boost::function<boost::optional<std::string> (DataSourceType *, const std::string &)> m_setter;
};


///////////////////////////////////////////////////////////////////////////////////


class QuantityEditConcept : public BaseConcept
{
  public:

  QuantityEditConcept(QString t_headingLabel, QString t_modelUnits, QString t_siUnits, QString t_ipUnits, bool t_isIP)
    : BaseConcept(t_headingLabel),
      m_modelUnits(t_modelUnits),
      m_siUnits(t_siUnits),
      m_ipUnits(t_ipUnits),
      m_isIP(t_isIP)
  {
  }

  virtual double get(const model::ModelObject & obj) = 0;
  virtual bool set(const model::ModelObject & obj, double) = 0;

  QString modelUnits() const { return m_modelUnits; }
  QString siUnits() const { return m_siUnits; }
  QString ipUnits() const { return m_ipUnits; }
  bool isIP() const { return m_isIP; }

  private:

  QString m_modelUnits;
  QString m_siUnits;
  QString m_ipUnits;
  bool m_isIP;
}; 

template<typename DataSourceType>
class QuantityEditConceptImpl : public QuantityEditConcept
{
  public:

  QuantityEditConceptImpl(QString t_headingLabel,
    boost::function<double (DataSourceType *)>  t_getter,
    boost::function<bool (DataSourceType *, double)> t_setter)
    : QuantityEditConcept(t_headingLabel),
      m_getter(t_getter),
      m_setter(t_setter)
  {
  }

  virtual double get(const model::ModelObject & t_obj)
  {
    DataSourceType obj = t_obj.cast<DataSourceType>();
    return m_getter(&obj);
  }

  virtual bool set(const model::ModelObject & t_obj, double value)
  {
    DataSourceType obj = t_obj.cast<DataSourceType>();
    return m_setter(&obj,value);
  }

  private:

  boost::function<double (DataSourceType *)>  m_getter;
  boost::function<bool (DataSourceType *, double)> m_setter;

};


///////////////////////////////////////////////////////////////////////////////////
  

class UnsignedEditConcept : public BaseConcept
{
  public:

  UnsignedEditConcept(QString t_headingLabel)
    : BaseConcept(t_headingLabel)
  {
  }

  virtual unsigned get(const model::ModelObject & obj) = 0;
  virtual bool set(const model::ModelObject & obj, unsigned) = 0;
}; 

template<typename DataSourceType>
class UnsignedEditConceptImpl : public UnsignedEditConcept
{
  public:

  UnsignedEditConceptImpl(QString t_headingLabel, 
    boost::function<unsigned (DataSourceType *)>  t_getter, 
    boost::function<bool (DataSourceType *, unsigned)> t_setter)
    : UnsignedEditConcept(t_headingLabel),
      m_getter(t_getter),
      m_setter(t_setter)
  {
  }

  virtual unsigned get(const model::ModelObject & t_obj)
  {
    DataSourceType obj = t_obj.cast<DataSourceType>();
    return m_getter(&obj);
  }

  virtual bool set(const model::ModelObject & t_obj, unsigned value)
  {
    DataSourceType obj = t_obj.cast<DataSourceType>();
    return m_setter(&obj,value);
  }

  private:

  boost::function<unsigned (DataSourceType *)>  m_getter;
  boost::function<bool (DataSourceType *, unsigned)> m_setter;
};


///////////////////////////////////////////////////////////////////////////////////
  

class DropZoneConcept : public BaseConcept
{
  public:

  DropZoneConcept(QString t_headingLabel)
    : BaseConcept(t_headingLabel)
  {
  }

  virtual boost::optional<model::ModelObject> get(const model::ModelObject & obj) = 0;
  virtual bool set(const model::ModelObject & obj, const model::ModelObject &) = 0;
}; 

template<typename ValueType, typename DataSourceType>
class DropZoneConceptImpl : public DropZoneConcept
{
  public:

  DropZoneConceptImpl(QString t_headingLabel, 
    boost::function<boost::optional<ValueType> (DataSourceType *)>  t_getter, 
    boost::function<bool (DataSourceType *, const ValueType &)> t_setter)
    : DropZoneConcept(t_headingLabel),
      m_getter(t_getter),
      m_setter(t_setter)
  {
  }

  virtual boost::optional<model::ModelObject> get(const model::ModelObject & t_obj)
  {
    DataSourceType obj = t_obj.cast<DataSourceType>();

    return boost::optional<model::ModelObject>(m_getter(&obj));
  }

  virtual bool set(const model::ModelObject & t_obj, const model::ModelObject & t_value)
  {
    DataSourceType obj = t_obj.cast<DataSourceType>();
    ValueType value = t_value.cast<ValueType>();
    return m_setter(&obj,value);
  }

  private:

  boost::function<boost::optional<ValueType> (DataSourceType *)>  m_getter;
  boost::function<bool (DataSourceType *, const ValueType &)> m_setter;
};


} // openstudio

#endif // OPENSTUDIO_OSCONCEPT_H
