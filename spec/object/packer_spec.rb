require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')
require_fixtures
require File.dirname(__FILE__) + "/../../lib/aqua/support/set"

Aqua.set_storage_engine('CouchDB') # to initialize CouchDB
CouchDB = Aqua::Store::CouchDB unless defined?( CouchDB )
Packer = Aqua::Packer unless defined?( Packer )
Rat = Aqua::Rat unless defined?( Rat )

describe Packer do
  before(:each) do
    @user = User.new(:username => 'Kane')
    @user_init = {"class"=>"Aqua::Stub", "init"=>{ "methods"=>{"username"=>"Kane"}, "class"=>"User", "id"=>"" }}
    @file = File.new(File.dirname(__FILE__) + '/../store/couchdb/fixtures_and_data/image_attach.png')
    @file_pack = { 
      'class' => 'Aqua::FileStub',
      'init' => 'image_attach.png', 
      "methods"=>{
        "content_type" => 'image/png', 
        "content_length" => {"class"=>"Fixnum", "init"=>"26551"}
      }
    } 
    @tempfile = Tempfile.new('temp.txt')
    @tempfile.write('I am a tempfile!')
    @tempfile.rewind          
  end  
  
  describe 'instances' do
    it 'should be itialized with the base object' do   
      pending
      @user._packer.base.should == @user
    end
    it 'should have externals'
    it 'should have attachments' 
  end  
  
  def pack( obj )
    Packer.pack_object( obj )
  end  
  
  describe 'class methods should pack' do
    it 'string' do 
      pack('string').should == Rat.new("string")
    end
      
    it 'times' do 
      time = Time.parse("12/23/69")
      pack(time).should == Rat.new( {"class" => "Time", "init" => time.to_s} )
    end
      
    it 'dates' do 
      date = Date.parse("12/23/69")
      pack(date).should == Rat.new( {"class" => "Date", "init" => date.to_s} )
    end
      
    it 'true' do 
      pack( true ).should == Rat.new( true )
    end
      
    it 'false' do
      pack( false ).should == Rat.new( false )
    end
    
    it 'Symbols' do 
      pack( :symbol ).should == Rat.new( {"class" => "Symbol", "init" => "symbol"} )
    end  
     
    it 'Fixnums' do
      pack( 1234 ).should == Rat.new( {"class" => "Fixnum", 'init' => '1234'} )
    end
      
    it 'Bignums' do
      pack( 12345678901234567890 ).should == 
        Rat.new( { "class" => 'Bignum', 'init' => '12345678901234567890' } )
    end
      
    it 'Floats' do
      pack( 1.681 ).should == Rat.new( { "class" => 'Float', 'init' => '1.681' } )
    end
      
    it 'Rationals' do
      pack( Rational( 1, 17 ) ).should == Rat.new( { "class" => 'Rational', 'init' => ['1','17'] } )
    end
    
    it 'Ranges' do
      pack( 1..3 ).should == Rat.new( { "class" => 'Range', 'init' => '1..3' } )
    end
      
    it 'arrays of string' do 
      pack( ['one', 'two'] ).should == Rat.new( {"class" => 'Array', 'init' => ['one', 'two'] } ) 
    end
    
    it 'mixed arrays' do
      pack( [1, :two] ).should == 
        Rat.new({"class" => 'Array', 'init' => [{"class"=>"Fixnum", "init"=>"1"}, {"class"=>"Symbol", "init"=>"two"} ]})
    end  
    
    it 'arrays with externals' do 
      user = User.new(:username => 'Kane')
      pack( [user, 1] ).should == Rat.new(
        {
          'class' => 'Array', 
          'init' => [
            @user_init, 
            {"class"=>"Fixnum", "init"=>"1"}
           ]
        }, { user => '[0]'} )                  
    end 
    
    it 'arrays with deeply nested externals' do
      user = User.new(:username => 'Kane')
      nested_pack = pack( ['layer 1', ['layer 2', ['layer 3', user ] ] ] )
      nested_pack.should == Rat.new(
        {
          'class' => 'Array', 
          'init' => [ 'layer 1',
            {
              'class' => 'Array',
              'init' => [ 'layer 2',
                {
                  'class' => 'Array',
                  'init' => [ 'layer 3', @user_init ]
                }
              ]
            }
          ] 
        },
        {user => '[1][1][1]'}
      )
    end   
    
    it 'array derivatives' do 
      array_derivative = ArrayUdder.new
      array_derivative[0] = 'zero index'
      array_derivative.udder # initializes an ivar
      pack( array_derivative ).should == Rat.new(
        {
          'class' => "ArrayUdder", 
          'init' => ['zero index'], 
          "ivars"=>{"@udder"=>"Squeeze out some array milk"}
        }
      )  
    end  
    
      
    it 'hashes' do 
      pack({'1' => 'one'}).should == Rat.new( {'class' => 'Hash', 'init' => {'1' => 'one'}} )
    end
      
    it 'hashes with externals' do 
      user = User.new(:username => 'Kane')
      pack({'user' => user}).should == Rat.new(
        {'class' => 'Hash', 'init' => {
          'user' => @user_init
        }}, 
        {user => "['user']"} 
      )
    end
      
    it 'hashes with object keys' do 
      pack({1 => 'one'}).should == Rat.new(
        {'class' => 'Hash', 'init' => { 
          '/_OBJECT_0' => 'one',
          '/_OBJECT_KEYS' => [{"class"=>"Fixnum", "init"=>"1"}]
        } }
      )
    end
      
    it 'hashes with externals as object keys' do 
      user = User.new(:username => 'Kane')
      pack({ user => 'user'}).should == Rat.new(
        { 'class' => 'Hash', 'init' => {
          '/_OBJECT_0' => 'user', 
          '/_OBJECT_KEYS' => [@user_init]
        }},
        { user => "['/_OBJECT_KEYS'][0]" }
      )
    end
      
    it 'open structs' do
      # open structs store keys as symbols internally, as such there is the object keys below ...
      user = User.new(:username => 'Kane') 
      struct = OpenStruct.new( :user => user ) 
      pack( struct ).should == Rat.new(
        { 'class' => 'OpenStruct', 
          'init' => { 
            '/_OBJECT_0' => @user_init,
            '/_OBJECT_KEYS' => [{"class"=>"Symbol", "init"=>"user"}]
           }
        },
        { user => "['/_OBJECT_0']" }
      )
    end  
    
    it 'files' do
      pack( @file ).should == Rat.new( @file_pack , {}, [ @file ] )
    end
      
    it 'arrays with files' do 
      pack( [@file, 1] ).should == Rat.new({
        'class' => 'Array', 
        'init' => [
          @file_pack, 
          {"class"=>"Fixnum", "init"=>"1"}
         ]
       }, {}, [@file]
     ) 
    end
      
    it 'arrays with deeply nested files' do  
      nested_pack = pack( ['layer 1', ['layer 2', ['layer 3', @file ] ] ] )
      nested_pack.should == Rat.new(
        {
          'class' => 'Array', 
          'init' => [ 'layer 1',
            {
              'class' => 'Array',
              'init' => [ 'layer 2',
                {
                  'class' => 'Array',
                  'init' => [ 'layer 3', @file_pack ]
                }
              ]
            }
          ] 
        },
        {}, [@file]
      )                  
    end
      
    it 'hashes with files' do   
      pack({'attachment' => @file}).should == Rat.new(
        {'class' => 'Hash', 'init' => {
          'attachment' => @file_pack
        }}, 
        {}, [@file] 
      ) 
    end
      
    it 'hashes with file keys' do 
      pack({ @file => 'attachment'}).should == Rat.new(
        { 'class' => 'Hash', 'init' => {
          '/_OBJECT_0' => 'attachment', 
          '/_OBJECT_KEYS' => [@file_pack]
        }},
        {}, [@file]
      )  
    end 
    
    it 'hash derivatives' do 
      hashish = CannedHash.new( 1 => 'one' )
      hashish.yum # sets instance variable
      pack(hashish).should == Rat.new(
        {'class' => 'CannedHash', 'init' => { 
          '/_OBJECT_0' => 'one',
          '/_OBJECT_KEYS' => [{"class"=>"Fixnum", "init"=>"1"}]
        }, 'ivars' => {'@yum' => 'Corned Beef!'} }
      )
    end  
    
    it 'sets' do 
      pack(Set.new(['a', 'b'])).should == Rat.new(
        { 'class' => 'Set', 'init' =>{'class'=> 'Array', 'init' =>['a', 'b']} }
      )
    end 
    
    it 'aquatic embedded objects' do 
      log = Log.new(:message => "Hi!")
      pack( log ).should == Rat.new(
        {'class' => 'Log', 'ivars' => {'@message' => 'Hi!'}}
      )
    end  
    
    it 'aquatic base objects in non-stub form' do 
      pack( @user ).pack['class'].should == 'User' 
    end  
  end   
end   