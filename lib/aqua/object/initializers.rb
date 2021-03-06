# AQUA INITIALIZATION
# Some object store state in a fundamental way, not in instance variables, that needs to be initialized.
# Examples: Array, Numeric types, Hashes, Time ...
# You can make any object requiring this initialization savable to aqua by
#  * including the Aqua::To module and extending the Aqua::From module
#  * building your own methods for #to_aqua, #to_aqua_init, MyClass.aqua_init
# See set.rb in this file for more an example
module Aqua
  module Initializers 
    def self.included( klass ) 
      klass.class_eval do
        include InstanceMethods
        extend ClassMethods
        
        unless methods.include?( :transient_attr )
          include Aqua::Pack::HiddenAttributes
        end
      end
    end
    
    module InstanceMethods 
      def to_aqua( path = '' )
        rat = Aqua::Translator::Rat.new( { 'class' => to_aqua_class } ) 
        
        init_rat = to_aqua_init( path )
        rat.hord(init_rat, 'init')  
        
        ivar_rat = _pack_instance_vars( path )
        rat.eat( ivar_rat ) if ivar_rat && ivar_rat.pack['ivars'] && !ivar_rat.pack['ivars'].empty?
          
        rat
      end
      
      def to_aqua_class
        self.class.to_s
      end  
      
      def _pack_instance_vars( path )
        rat = Aqua::Translator::Rat.new
        ivar_rat = Translator.pack_ivars( self )
        ivar_rat.pack.empty? ? rat : rat.hord( ivar_rat, 'ivars' ) 
      end  
  
      def to_aqua_init( path )
        Aqua::Translator::Rat.new( self.to_s ) 
      end 
    end # InstanceMethods
    
    module ClassMethods 
    end # ClassMethods   
    
  end # Initializers
         
end  

[ TrueClass, FalseClass, Symbol, Time, Date, Fixnum, Bignum, Float, Rational, Hash, Array, OpenStruct, Range, File, Tempfile, String, NilClass].each do |klass|
  klass.class_eval { include Aqua::Initializers }
end 

class String
  def from_aqua( path='')
    self
  end  
  
  def to_aqua( path='' )
    Aqua::Translator::Rat.new( self )
  end 
end 

class TrueClass 
  def from_aqua( path='')
    true
  end  
  
  def to_aqua( path='')
    Aqua::Translator::Rat.new( true )
  end 
end  

class FalseClass
  def from_aqua( path='')
    false
  end  
  
  def to_aqua( path='' )
    Aqua::Translator::Rat.new( false )
  end
end   

class NilClass
  def self.aqua_init( init, opts=Aqua::Translator::Opts.new     )
    nil
  end
end  

class Symbol 
  def self.aqua_init( init, opts=Aqua::Translator::Opts.new     )
    init.to_sym
  end
  
  def _pack_instance_vars( path='')
    nil
  end 
end  

require 'date'  # for Date.parse
class Date
  transient_attr :sg, :of, :ajd
  
  def self.aqua_init( init, opts=Aqua::Translator::Opts.new     )
    parse( init )
  end 
  
  def _pack_instance_vars( path='')
    nil
  end       
end 

class Time 
  def self.aqua_init( init, opts=Aqua::Translator::Opts.new     )
    parse( init )
  end
end

class Fixnum
  def self.aqua_init( init, opts=Aqua::Translator::Opts.new     )
    init.to_i
  end
end

class Bignum
  def self.aqua_init( init, opts=Aqua::Translator::Opts.new     )
    init.to_i
  end
end  
   
class Float
  def self.aqua_init( init, opts=Aqua::Translator::Opts.new     )
    init.to_f
  end
end 

class Rational
  def to_aqua_init( path='') 
    Aqua::Translator::Rat.new( self.to_s.match(/(\d*)\/(\d*)/).to_a.slice(1,2) )
  end 
  
  def self.aqua_init( init, opts=Aqua::Translator::Opts.new     )
    Rational( init[0].to_i, init[1].to_i )
  end
  
  def _pack_instance_vars( path='')
    nil
  end       
end

class Range
  # todo: make this work for non int objects, time, date, etc ...
  def self.aqua_init( init, opts=Aqua::Translator::Opts.new ) 
    eval( init )
  end
end     

class Array
  def to_aqua_init( path = '' )
    rat = Aqua::Translator::Rat.new([])
    self.each_with_index do |obj, index|
      local_path = path + "[#{index}]" 
      obj_rat = Aqua::Translator.pack_object( obj, local_path )
      rat.eat( obj_rat )  
    end
    rat   
  end
  
  def self.aqua_init( init, opts=Aqua::Translator::Opts.new ) 
    # todo: make opts opts.path follow the path through the base object
    array_init = init.map{ |obj| Aqua::Translator.unpack_object(obj, opts) } 
    # new is neccessary to make sure array derivatives maintain their class
    # without having to override aqua_init! 
    self == Array ? array_init : new( array_init ) 
  end 
end


class Hash
  def to_aqua_init( path='')
    rat = Aqua::Translator::Rat.new
    self.each do |raw_key, value|
      key_class = raw_key.class
      if key_class == String
        key = raw_key
      else # key is an object 
        index = aqua_next_object_index( rat.pack )  
        key = self.class.aqua_object_key_index( index )
        key_rat = Aqua::Translator.pack_object( raw_key, path+"['#{self.class.aqua_key_register}'][#{index}]")
        rat.hord( key_rat, [self.class.aqua_key_register, index] )
      end
      obj_rat = Aqua::Translator.pack_object( value, path+"['#{key}']" )
      rat.hord( obj_rat, key )
    end
    rat 
  end
  
  def self.aqua_key_register
    "#{aqua_key_register_prefix}KEYS".freeze
  end
  
  def self.aqua_key_register_prefix
    "/_OBJECT_"
  end  
  
  def self.aqua_object_key_index( index ) 
    "#{aqua_key_register_prefix}#{index}"
  end    
  
  def aqua_next_object_index( hash )
    hash[self.class.aqua_key_register] ||= []
    hash[self.class.aqua_key_register].size
  end  
  
  def self.aqua_init( init, opts=Aqua::Translator::Opts.new )
    unpacked = {}
    init.each do |key, value|
      unless key == aqua_key_register
        if key.match(/^#{aqua_key_register_prefix}(\d*)$/)
          index = $1.to_i
          key = Aqua::Translator.unpack_object( init[aqua_key_register][index], opts )
        end 
        opts.path += "[#{key}]" 
        value = Aqua::Translator.unpack_object( value, opts )
        unpacked[ key ] = value 
      end  
    end
    self == Hash ? unpacked : new( unpacked )  
  end 
end

class OpenStruct
  transient_attr :table
  
  def to_aqua_init( path='' ) 
    instance_variable_get("@table").to_aqua_init( path )
  end
  
  def self.aqua_init( init, opts=Aqua::Translator::Opts.new )
    init = Hash.aqua_init( init, opts )
    new( init )
  end
end 

module Aqua
  module FileInitializations 
    def to_aqua( opts=Aqua::Translator::Opts.new )
      rat = Aqua::Translator::Rat.new(
        { 
          'class' => to_aqua_class,
          'init' => {
            'id' => filename,
            'methods' => {
              'content_type' => content_type,
              'content_length' => content_length 
            }
          }  
        }, {}, [self]
      )
        
      ivar_rat = _pack_instance_vars( path )
      rat.eat( ivar_rat ) if ivar_rat && ivar_rat.pack['ivars'] && !ivar_rat.pack['ivars'].empty?
          
      rat 
    end
    
    def content_length 
      if len = stat.size
        rat = Aqua::Translator.pack_object( len )
        rat.pack
      else
        ''
      end  
    end 
    
    def content_type 
      mime = MIME::Types.type_for( self.path )
      mime && mime.first ? mime.first.to_s : ''
    end     
    
    def to_aqua_class
      'Aqua::FileStub'
    end   
       
    def filename
      path.match(/([^\/]*)\z/).to_s
    end
      
  end # FileInitializations
end # Aqua
   
class File
  include Aqua::FileInitializations        
end

class Tempfile
  include Aqua::FileInitializations
  
  transient_attr :clean_proc, :data, :tmpname, :tmpfile, :_dc_obj
  
  def filename
    path.match(/([^\/]*)\.\d*\.\d*\z/).captures.first
  end
end       