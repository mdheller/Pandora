#!/usr/bin/env ruby
# encoding: UTF-8
# coding: UTF-8

# The Pandora. Free peer-to-peer information system
# RU: Пандора. Свободная пиринговая информационная система
#
# This program is distributed under the GNU GPLv2
# RU: Эта программа распространяется под GNU GPLv2
# 2012 (c) Michael Galyuk
# RU: 2012 (c) Михаил Галюк

$ruby_low19 = RUBY_VERSION<'1.9'
if $ruby_low19
  $KCODE='UTF-8'
  begin
    require 'jcode'
    $jcode_on = true
  rescue Exception
    $jcode_on = false
  end
  if (RUBY_VERSION<'1.8.7')
    puts 'The Pandora needs Ruby 1.8.7 or higher (current '+RUBY_VERSION+')'
    exit(10)
  end
  require 'iconv'
  class AsciiString < String
    def force_encoding(enc)
      self
    end
  end
else
  class AsciiString < String
    def initialize(*args)
      super(*args)
      force_encoding('ASCII-8BIT')
    end
  end
  Encoding.default_external = 'UTF-8'
  Encoding.default_internal = 'UTF-8' #BINARY ASCII-8BIT UTF-8
end

# Platform detection
# RU: Определение платформы
def os_family
  case RUBY_PLATFORM
    when /ix/i, /ux/i, /gnu/i, /sysv/i, /solaris/i, /sunos/i, /bsd/i
      'unix'
    when /win/i, /ming/i
      'windows'
    else
      'other'
  end
end

# Paths and files  ('join' gets '/' for Linux and '\' for Windows)
# RU: Пути и файлы ('join' дает '/' для Линукса и '\' для Винды)
#if os_family != 'windows'
$pandora_root_dir = Dir.pwd                                       # Current Pandora directory
#  $pandora_root_dir = File.expand_path(File.dirname(__FILE__))     # Script directory
#else
#  $pandora_root_dir = '.'     # It prevents a bug with cyrillic paths in Win XP
#end
$pandora_base_dir = File.join($pandora_root_dir, 'base')            # Default database directory
$pandora_view_dir = File.join($pandora_root_dir, 'view')            # Media files directory
$pandora_model_dir = File.join($pandora_root_dir, 'model')          # Model description directory
$pandora_lang_dir = File.join($pandora_root_dir, 'lang')            # Languages directory
$pandora_sqlite_db = File.join($pandora_base_dir, 'pandora.sqlite')  # Default database file
$pandora_sqlite_db2 = File.join($pandora_base_dir, 'pandora2.sqlite')  # Default database file

# If it's runned under WinOS, redirect console output to file, because of rubyw.exe crush
# RU: Если под Виндой, то перенаправить консольный вывод в файл из-за краша rubyw.exe
if os_family=='windows'
  $stdout.reopen(File.join($pandora_base_dir, 'stdout.log'), 'w')
  $stderr = $stdout
end

# ==Including modules
# ==RU: Подключение модулей

# XML requires for preference setting and exports
# RU: XML нужен для хранения настроек и выгрузок
require 'rexml/document'
require 'zlib'
require 'socket'
require 'digest'
require 'base64'
require 'net/http'
require 'net/https'

# The particular sqlite database interface
# RU: Отдельный модуль для подключения к базам sqlite
begin
  require 'sqlite3'
  $sqlite3_on = true
rescue Exception
  $sqlite3_on = false
end

# The particular mysql database interface
# RU: Отдельный модуль для подключения к базам mysql
begin
  require 'mysql'
  $mysql_on = true
rescue Exception
  $mysql_on = false
end

# NCurses is console output interface
# RU: Интерфейс для вывода псевдографики в текстовом режиме
begin
  require 'ncurses'
  $ncurses_on = true
rescue Exception
  $ncurses_on = false
end

# GTK is cross platform graphical user interface
# RU: Кроссплатформенный оконный интерфейс
begin
  require 'gtk2'
  $gtk2_on = true
rescue Exception
  $gtk2_on = false
end

# OpenSSL is a crypto library
# RU: Криптографическая библиотека
begin
  require 'openssl'
  $openssl_on = true
rescue Exception
  $openssl_on = false
end

# Default language when environment LANG variable is not defined
# RU: Язык по умолчанию, когда не задана переменная окружения LANG
$lang = 'ru'

# Define environment parameters
# RU: Определить переменные окружения
lang = ENV['LANG']
if (lang.is_a? String) and (lang.size>1)
  $lang = lang[0, 2].downcase
end
#$lang = 'en'

# Default values of variables
# RU: Значения переменных по умолчанию
$host = '127.0.0.1'
$port = 5577
$base_index = 0
$pandora_parameters = []

# Expand the arguments of command line
# RU: Разобрать аргументы командной строки

arg = nil
val = nil
next_arg = nil
while (ARGV.length>0) or next_arg
  if next_arg
    arg = next_arg
    next_arg = nil
  else
    arg = ARGV.shift
  end
  if arg.is_a? String and (arg[0,1]=='-')
    if ARGV.length>0
      next_arg = ARGV.shift
    end
    if next_arg and next_arg.is_a? String and (next_arg[0,1] != '-')
      val = next_arg
      next_arg = nil
    end
  end
  case arg
    when '-h','--host'
      $host = val if val
    when '-p','--port'
      $port = val.to_i if val
    when '-bi'
      $base_index = val.to_i if val
    when '--shell', '--help', '/?', '-?'
      runit = '  '
      if arg=='--shell' then
        runit += 'pandora.sh'
      else
        runit += 'ruby pandora.rb'
      end
      runit += ' '
      puts 'Оriginal Pandora params for examples:'
      puts runit+'-h localhost   - set listen address'
      puts runit+'-p 5577        - set listen port'
      puts runit+'-bi 0          - set index of database'
      Thread.exit
  end
  val = nil
end

# GStreamer is a media library
# RU: Обвязка для медиа библиотеки GStreamer
begin
  require 'gst'
  $gst_on = true
rescue Exception
  $gst_on = false
end

# Array of localization phrases
# RU: Вектор переведеных фраз
$lang_trans = {}

# Translation of the phrase
# RU: Перевод фразы
def _(frase)
  trans = $lang_trans[frase]
  if not trans or (trans.size==0) and frase and (frase.size>0)
    trans = frase
  end
  trans
end

LM_Error    = 0
LM_Warning  = 1
LM_Info     = 2
LM_Trace    = 3

def level_to_str(level)
  mes = ''
  case level
    when LM_Error
      mes = _('Error')
    when LM_Warning
      mes = _('Warning')
    when LM_Trace
      mes = _('Trace')
  end
  mes = '['+mes+'] ' if mes != ''
end

$view = nil

# Log message
# RU: Добавить сообщение в лог
def log_message(level, mes)
  mes = level_to_str(level).to_s+mes
  if $view
    $view.buffer.insert($view.buffer.end_iter, mes+"\n")
    #$view.move_viewport(Gtk::SCROLL_ENDS, 1)
    $view.parent.vadjustment.value = $view.parent.vadjustment.upper
  else
    puts mes
  end
end

# ==============================================================================
# == Base module of Pandora
# == RU: Базовый модуль Пандора
module PandoraKernel

  # Load translated phrases
  # RU: Загрузить переводы фраз
  def self.load_language(lang='ru')

    def self.unslash_quotes(str)
      str ||= ''
      str.gsub('\"', '"')
    end

    def self.addline(str, line)
      line = unslash_quotes(line)
      if (not str) or (str=='')
        str = line
      else
        str = str.to_s + "\n" + line.to_s
      end
      str
    end

    def self.spaces_after(line, pos)
      i = line.size-1
      while (i>=pos) and ((line[i, 1]==' ') or (line[i, 1]=="\t"))
        i -= 1
      end
      (i<pos)
    end

    $lang_trans = {}
    langfile = File.join($pandora_lang_dir, lang+'.txt')
    if File.exist?(langfile)
      scanmode = 0
      frase = ''
      trans = ''
      IO.foreach(langfile) do |line|
        if (line.is_a? String) and (line.size>0)
          #line = line[0..-2] if line[-1,1]=="\n"
          #line = line[0..-2] if line[-1,1]=="\r"
          line.chomp!
          end_is_found = false
          if scanmode==0
            end_is_found = true
            if (line.size>0) and (line[0, 1] != '#')
              if line[0, 1] != '"'
                frase, trans = line.split('=>')
                $lang_trans[frase] = trans if (frase != '') and (trans != '')
              else
                line = line[1..-1]
                frase = ''
                trans = ''
                end_is_found = false
              end
            end
          end

          if not end_is_found
            if scanmode<2
              i = line.index('"=>"')
              if i
                frase = addline(frase, line[0, i])
                line = line[i+4, line.size-i-4]
                scanmode = 2 #composing a trans
              else
                scanmode = 1 #composing a frase
              end
            end
            if scanmode==2
              k = line.rindex('"')
              if k and ((k==0) or (line[k-1, 1] != "\\"))
                end_is_found = ((k+1)==line.size) or spaces_after(line, k+1)
                if end_is_found
                  trans = addline(trans, line[0, k])
                end
              end
            end

            if end_is_found
              $lang_trans[frase] = trans if (frase != '') and (trans != '')
              scanmode = 0
            else
              if scanmode < 2
                frase = addline(frase, line)
                scanmode = 1 #composing a frase
              else
                trans = addline(trans, line)
              end
            end
          end
        end
      end
    end
  end

  # Save language phrases
  # RU: Сохранить языковые фразы
  def self.save_as_language(lang='ru')

    def self.slash_quotes(str)
      str.gsub('"', '\"')
    end

    def self.there_are_end_space(str)
      lastchar = str[str.size-1, 1]
      (lastchar==' ') or (lastchar=="\t")
    end

    langfile = File.join($pandora_lang_dir, lang+'.txt')
    File.open(langfile, 'w') do |file|
      file.puts('# Pandora language file EN=>'+lang.upcase)
      $lang_trans.each do |value|
        if (not value[0].index('"')) and (not value[1].index('"')) \
          and (not value[0].index("\n")) and (not value[1].index("\n")) \
          and (not there_are_end_space(value[0])) and (not there_are_end_space(value[1]))
        then
          str = value[0]+'=>'+value[1]
        else
          str = '"'+slash_quotes(value[0])+'"=>"'+slash_quotes(value[1])+'"'
        end
        file.puts(str)
      end
    end
  end

  # Type translation Ruby->SQLite
  # RU: Трансляция типа Ruby->SQLite
  def self.ruby_type_to_sqlite_type(rt, size)
    rt_str = rt.to_s
    size_i = size.to_i
    case rt_str
      when 'Integer', 'Word', 'Byte', 'Coord'
        'INTEGER'
      when 'Float'
        'REAL'
      when 'Number', 'Panhash'
        'NUMBER'
      when 'Date', 'Time'
        'DATE'
      when 'String'
        if (1<=size_i) and (size_i<=127)
          'VARCHAR('+size.to_s+')'
        else
          'TEXT'
        end
      when 'Text'
        'TEXT'
      when '',nil
        'NUMBER'
      when 'Blob'
        'BLOB'
      else
        'NUMBER'
    end
  end

  def self.ruby_val_to_sqlite_val(v)
    if v.is_a? Time
      v = v.to_i
    elsif v.is_a? TrueClass
      v = 1
    elsif v.is_a? FalseClass
      v = 0
    end
    v
  end

  # Table definitions of SQLite from fields definitions
  # RU: Описание таблицы SQLite из описания полей
  def self.panobj_fld_to_sqlite_tab(panobj_flds)
    res = ''
    panobj_flds.each do |fld|
      res = res + ', ' if res != ''
      res = res + fld[FI_Id].to_s + ' ' + PandoraKernel::ruby_type_to_sqlite_type(fld[FI_Type], fld[FI_Size])
    end
    res = '(id INTEGER PRIMARY KEY AUTOINCREMENT, ' + res + ')' if res != ''
    res
  end

  # Abstract database adapter
  # RU:Абстрактный адаптер к БД
  class DatabaseSession
    NAME = "Сеанс подключения"
    attr_accessor :connected, :conn_param, :def_flds
    def initialize
      @connected = FALSE
      @conn_param = ''
      @def_flds = {}
    end
    def connect
    end
    def create_table(table_name)
    end
    def select_table(table_name, afilter=nil, fields=nil, sort=nil, limit=nil)
    end
  end

  TI_Name  = 0
  TI_Type  = 1
  TI_Desc  = 2

  # SQLite adapter
  # RU: Адаптер SQLite
  class SQLiteDbSession < DatabaseSession
    NAME = "Сеанс SQLite"
    attr_accessor :db, :exist
    def connect
      if not connected
        @db = SQLite3::Database.new(conn_param)
        @connected = TRUE
        @exist = {}
      end
      connected
    end
    def create_table(table_name, recreate=false)
      connect
      tfd = db.table_info(table_name)
      #p tfd
      tfd.collect! { |x| x['name'] }
      if (not tfd) or (tfd == [])
        @exist[table_name] = FALSE
      else
        @exist[table_name] = TRUE
      end
      tab_def = PandoraKernel::panobj_fld_to_sqlite_tab(def_flds[table_name])
      #p tab_def
      if (! exist[table_name] or recreate) and tab_def
        if exist[table_name] and recreate
          res = db.execute('DROP TABLE '+table_name)
        end
        p 'CREATE TABLE '+table_name+' '+tab_def
        res = db.execute('CREATE TABLE '+table_name+' '+tab_def)
        @exist[table_name] = TRUE
      end
      exist[table_name]
    end
    def fields_table(table_name)
      connect
      tfd = db.table_info(table_name)
      tfd.collect { |x| [x['name'], x['type']] }
    end
    def escape_like_mask(mask)
      #SELECT * FROM mytable WHERE myblob LIKE X'0025';
      #SELECT * FROM mytable WHERE quote(myblob) LIKE 'X''00%';     end
      #Is it possible to pre-process your 10 bytes and insert e.g. symbol '\'
      #before any '\', '_' and '%' symbol? After that you can query
      #SELECT * FROM mytable WHERE myblob LIKE ? ESCAPE '\'
      #SELECT * FROM mytable WHERE substr(myblob, 1, 1) = X'00';
      #SELECT * FROM mytable WHERE substr(myblob, 1, 10) = ?;
      if mask.is_a? String
        mask.gsub!('$', '$$')
        mask.gsub!('_', '$_')
        mask.gsub!('%', '$%')
        #query = AsciiString.new(query)
        #i = query.size
        #while i>0
        #  if ['$', '_', '%'].include? query[i]
        #    query = query[0,i+1]+'$'+query[i+1..-1]
        #  end
        #  i -= 1
        #end
      end
      mask
    end
    def select_table(table_name, filter=nil, fields=nil, sort=nil, limit=nil, like_filter=nil)
      connect
      tfd = fields_table(table_name)
      if (not tfd) or (tfd == [])
        @selection = [['<no>'],['<base>']]
      else
        sql_values = []
        if filter.is_a? Hash
          sql2 = ''
          filter.each do |n,v|
            if n
              sql2 = sql2 + ' AND ' if sql2 != ''
              sql2 = sql2 + n.to_s + '=?'
              sql_values << v
            end
          end
          filter = sql2
        end
        if like_filter.is_a? Hash
          sql2 = ''
          like_filter.each do |n,v|
            if n
              sql2 = sql2 + ' AND ' if sql2 != ''
              sql2 = sql2 + n.to_s + 'LIKE ?'
              sql_values << v
            end
          end
          like_filter = sql2
        end
        fields ||= '*'
        sql = 'SELECT '+fields+' FROM '+table_name
        filter = nil if (filter and (filter == ''))
        like_filter = nil if (like_filter and (like_filter == ''))
        if filter or like_filter
          sql = sql + ' WHERE'
          sql = sql + ' ' + filter if filter
          if like_filter
            sql = sql + ' AND' if filter
            sql = sql + ' ' + like_filter
          end
        end
        if sort and (sort > '')
          sql = sql + ' ORDER BY '+sort
        end
        if limit
          sql = sql + ' LIMIT '+limit.to_s
        end
        #p 'select  sql='+sql.inspect
        @selection = db.execute(sql, sql_values)
      end
    end
    def update_table(table_name, values, names=nil, filter=nil)
      res = false
      connect
      sql = ''
      sql_values = []
      sql_values2 = []

      if filter.is_a? Hash
        sql2 = ''
        filter.each do |n,v|
          if n
            sql2 = sql2 + ' AND ' if sql2 != ''
            sql2 = sql2 + n.to_s + '=?'
            #v.force_encoding('ASCII-8BIT')  and v.is_a? String
            #v = AsciiString.new(v) if v.is_a? String
            sql_values2 << v
          end
        end
        filter = sql2
      end

      if (not values) and (not names) and filter
        sql = 'DELETE FROM ' + table_name + ' where '+filter
      elsif values.is_a? Array and names.is_a? Array
        tfd = db.table_info(table_name)
        tfd_name = tfd.collect { |x| x['name'] }
        tfd_type = tfd.collect { |x| x['type'] }
        if filter
          values.each_with_index do |v,i|
            fname = names[i]
            if fname
              sql = sql + ',' if sql != ''
              #v.is_a? String
              #v.force_encoding('ASCII-8BIT')  and v.is_a? String
              #v = AsciiString.new(v) if v.is_a? String
              v = PandoraKernel.ruby_val_to_sqlite_val(v)
              sql_values << v
              sql = sql + fname.to_s + '=?'
            end
          end

          sql = 'UPDATE ' + table_name + ' SET ' + sql
          if filter and filter != ''
            sql = sql + ' where '+filter
          end
        else
          sql2 = ''
          values.each_with_index do |v,i|
            fname = names[i]
            if fname
              sql = sql + ',' if sql != ''
              sql2 = sql2 + ',' if sql2 != ''
              sql = sql + fname.to_s
              sql2 = sql2 + '?'
              #v.force_encoding('ASCII-8BIT')  and v.is_a? String
              #v = AsciiString.new(v) if v.is_a? String
              v = PandoraKernel.ruby_val_to_sqlite_val(v)
              sql_values << v
            end
          end
          sql = 'INSERT INTO ' + table_name + '(' + sql + ') VALUES(' + sql2 + ')'
        end
      end
      tfd = fields_table(table_name)
      if tfd and (tfd != [])
        sql_values = sql_values+sql_values2
        p '1upd_tab: sql='+sql.inspect
        p '2upd_tab: sql_values='+sql_values.inspect
        res = db.execute(sql, sql_values)
        #p 'upd_tab: db.execute.res='+res.inspect
        res = true
      end
      #p 'upd_tab: res='+res.inspect
      res
    end
  end

  # Repository manager
  # RU: Менеджер хранилищ
  class RepositoryManager
    attr_accessor :base_list
    def initialize
      super
      @base_list = # динамический список баз
        [['robux', 'sqlite3,', $pandora_sqlite_db, nil],
         ['robux', 'sqlite3,', $pandora_sqlite_db2, nil],
         ['robux', 'mysql', ['robux.biz', 'user', 'pass', 'oscomm'], nil]]
    end
    def get_adapter(panobj, table_ptr, recreate=false)
      #find db_ptr in db_list
      adap = nil
      base_des = base_list[$base_index]
      if not base_des[3]
        adap = SQLiteDbSession.new
        adap.conn_param = base_des[2]
        base_des[3] = adap
      else
        adap = base_des[3]
      end
      table_name = table_ptr[1]
      adap.def_flds[table_name] = panobj.def_fields
      if (not table_name) or (table_name=='') then
        puts 'No table name for ['+panobj.name+']'
      else
        adap.create_table(table_name, recreate)
        #adap.create_table(table_name, TRUE)
      end
      adap
    end
    def get_tab_select(panobj, table_ptr, filter=nil, fields=nil, sort=nil, limit=nil)
      adap = get_adapter(panobj, table_ptr)
      adap.select_table(table_ptr[1], filter, fields, sort, limit)
    end
    def get_tab_update(panobj, table_ptr, values, names, filter='')
      res = false
      recreate = ((not values) and (not names) and (not filter))
      adap = get_adapter(panobj, table_ptr, recreate)
      if recreate
        res = (adap != nil)
      else
        res = adap.update_table(table_ptr[1], values, names, filter)
      end
      res
    end
    def get_tab_fields(panobj, table_ptr)
      adap = get_adapter(panobj, table_ptr)
      adap.fields_table(table_ptr[1])
    end
  end

  # Global poiter to repository manager
  # RU: Глобальный указатель на менеджер хранилищ
  $repositories = RepositoryManager.new

  # Plural or single name
  # RU: Имя во множественном или единственном числе
  def self.get_name_or_names(name, plural=false)
    sname, pname = name.split('|')
    if plural==false
      res = sname
    elsif (not pname) or (pname=='')
      res = sname
      res[-1]='ie' if res[-1,1]=='y'
      res = res+'s'
    else
      res = pname
    end
    res
  end

  # Convert string of bytes to hex string
  # RU: Преобрзует строку байт в 16-й формат
  def self.bytes_to_hex(bytes)
    res = AsciiString.new
    #res.force_encoding('ASCII-8BIT')
    if bytes
      bytes.each_byte do |b|
        res << ('%02x' % b)
      end
    end
    res
  end

  def self.hex_to_bytes(hexstr)
    bytes = AsciiString.new
    hexstr = '0'+hexstr if hexstr.size % 2 > 0
    ((hexstr.size+1)/2).times do |i|
      bytes << hexstr[i*2,2].to_i(16).chr
    end
    AsciiString.new(bytes)
  end

  # Convert big integer to string of bytes
  # RU: Преобрзует большое целое в строку байт
  def self.bigint_to_bytes(bigint)
    bytes = AsciiString.new
    #bytes = ''
    #bytes.force_encoding('ASCII-8BIT')
    if bigint<=0xFF
      bytes << [bigint].pack('C')
    else
      #not_null = true
      #while not_null
      #  bytes = (bigint & 255).chr + bytes
      #  bigint = bigint >> 8
      #  not_null = (bigint>0)
      #end
      hexstr = bigint.to_s(16)
      hexstr = '0'+hexstr if hexstr.size % 2 > 0
      ((hexstr.size+1)/2).times do |i|
        bytes << hexstr[i*2,2].to_i(16).chr
      end
    end
    AsciiString.new(bytes)
  end

  # Convert string of bytes to big integer
  # RU: Преобрзует строку байт в большое целое
  def self.bytes_to_bigint(bytes)
    res = nil
    if bytes
      hexstr = bytes_to_hex(bytes)
      res = OpenSSL::BN.new(hexstr, 16)
    end
    res
  end

  def self.bytes_to_int(bytes)
    res = 0
    i = bytes.size
    bytes.each_byte do |b|
      i -= 1
      res += (b << 8*i)
    end
    res
  end

  # Fill string by zeros from left to defined size
  # RU: Заполнить строку нулями слева до нужного размера
  def self.fill_zeros_from_left(data, size)
    #data.force_encoding('ASCII-8BIT')
    data = AsciiString.new(data)
    if data.size<size
      data = [0].pack('C')*(size-data.size) + data
    end
    #data.ljust(size, 0.chr)
    data = AsciiString.new(data)
  end

  # Property indexes of field definition array
  # RU: Индексы свойств в массиве описания полей
  FI_Id      = 0
  FI_Name    = 1
  FI_Type    = 2
  FI_Size    = 3
  FI_Pos     = 4
  FI_FSize   = 5
  FI_Hash    = 6
  FI_View    = 7
  FI_LName   = 8
  FI_VFName  = 9
  FI_Index   = 10
  FI_LabOr   = 11
  FI_NewRow  = 12
  FI_VFSize  = 13
  FI_Value   = 14
  FI_Widget  = 15
  FI_Label   = 16
  FI_LabW    = 17
  FI_LabH    = 18
  FI_WidW    = 19
  FI_WidH    = 20
  FI_Color   = 21

  $max_hash_len = 20

  def self.kind_from_panhash(panhash)
    kind = panhash[0].ord
  end

  def self.lang_from_panhash(panhash)
    lang = panhash[1].ord
  end

  # Base Pandora's object
  # RU: Базовый объект Пандоры
  class BasePanobject
    class << self
      def initialize(*args)
        super(*args)
        @ider = 'BasePanobject'
        @name = 'Базовый объект Пандоры'
        #@lang = true
        @tables = []
        @def_fields = []
        @def_fields_expanded = false
        @panhash_pattern = nil
        @panhash_ind = nil
        @modified_ind = nil
      end
      def ider
        @ider
      end
      def ider=(x)
        @ider = x
      end
      def kind
        @kind
      end
      def kind=(x)
        @kind = x
      end
      def sort
        @sort
      end
      def sort=(x)
        @sort = x
      end
      def panhash_ind
        @panhash_ind
      end
      def modified_ind
        @modified_ind
      end
      #def lang
      #  @lang
      #end
      #def lang=(x)
      #  @lang = x
      #end
      def def_fields
        @def_fields
      end
      def get_parent
        res = superclass
        res = nil if res == Object
        res
      end
      def field_des(fld_name)
        df = def_fields.detect{ |e| (e.is_a? Array) and (e[FI_Id].to_s == fld_name) or (e.to_s == fld_name) }
      end
      # The title of field in current language
      # "fd" must be field id or field description
      def field_title(fd)
        res = nil
        if fd.is_a? String
          res = fd
          fd = field_des(fd)
        end
        lang_exist = false
        if fd.is_a? Array
          res = fd[FI_LName]
          lang_exist = (res and (res != ''))
          res ||= fd[FI_Name]
          res ||= fd[FI_Id]
        end
        res = _(res) if not lang_exist
        res ||= ''
        res
      end
      def set_if_nil(f, fi, pfd)
        f[fi] ||= pfd[fi]
      end
      def decode_pos(pos=nil)
        pos ||= ''
        pos = pos.to_s
        new_row = 1 if pos.include?('|')
        ind = pos.scan(/[0-9\.\+]+/)
        ind = ind[0] if ind
        lab_or = pos.scan(/[a-z]+/)
        lab_or = lab_or[0] if lab_or
        lab_or = lab_or[0, 1] if lab_or
        if (not lab_or) or (lab_or=='u')
          lab_or = :up
        elsif (lab_or=='l')
          lab_or = :left
        elsif (lab_or=='d') or (lab_or=='b')
          lab_or = :down
        elsif (lab_or=='r')
          lab_or = :right
        else
          lab_or = :up
        end
        [ind, lab_or, new_row]
      end
      def set_view_and_len(fd)
        view = nil
        len = nil
        if (fd.is_a? Array) and fd[FI_Type]
          type = fd[FI_Type].to_s
          case type
            when 'Date'
              view = 'date'
              len = 10
            when 'Time'
              view = 'time'
              len = 16
            when 'Byte'
              view = 'byte'
              len = 3
            when 'Word'
              view = 'word'
              len = 5
            when 'Integer', 'Coord'
              view = 'integer'
              len = 10
            when 'Blog'
              if not fd[FI_Size] or fd[FI_Size].to_i>25
                view = 'base64'
              else
                view = 'hex'
              end
              #len = 24
            when 'Text'
              view = 'text'
              #len = 32
            when 'Panhash'
              view = 'panhash'
              len = 32
            when 'PHash', 'Phash'
              view = 'phash'
              len = 32
            else
              if type[0,7]=='Panhash'
                view = 'phash'
                len = 32
              end
          end
        end
        fd[FI_View] = view if view and (not fd[FI_View]) or (fd[FI_View]=='')
        fd[FI_FSize] = len if len and (not fd[FI_FSize]) or (fd[FI_FSize]=='')
        #p 'name,type,fsize,view,len='+[fd[FI_Name], fd[FI_Type], fd[FI_FSize], view, len].inspect
        [view, len]
      end
      def tab_fields(reinit=false)
        if (not @last_tab_fields) or reinit
          @last_tab_fields = repositories.get_tab_fields(self, tables[0])
          @last_tab_fields.each do |x|
            x[TI_Desc] = field_des(x[TI_Name])
          end
        end
        @last_tab_fields
      end
      def expand_def_fields_to_parent(reinit=false)
        if (not @def_fields_expanded) or reinit
          @def_fields_expanded = true
          # get undefined parameters from parent
          parent = get_parent
          if parent
            parent.expand_def_fields_to_parent
            if parent.def_fields.is_a? Array
              @def_fields.each do |f|
                if f.is_a? Array
                  pfd = parent.field_des(f[FI_Id])
                  if pfd.is_a? Array
                    set_if_nil(f, FI_LName, pfd)
                    set_if_nil(f, FI_Pos, pfd)
                    set_if_nil(f, FI_FSize, pfd)
                    set_if_nil(f, FI_Hash, pfd)
                    set_if_nil(f, FI_View, pfd)
                  end
                end
              end
            end
          end
          # calc indexes and form sizes, and sort def_fields
          df = def_fields
          if df.is_a? Array
            i = 0
            last_ind = 0.0
            df.each do |field|
              #p '===[field[FI_VFName], field[FI_View]]='+[field[FI_VFName], field[FI_View]].inspect
              set_view_and_len(field)
              fldsize = 0
              if field[FI_Size]
                fldsize = field[FI_Size].to_i
              end
              fldvsize = fldsize
              if (not field[FI_FSize] or (field[FI_FSize].to_i==0)) and (fldsize>0)
                field[FI_FSize] = fldsize
                field[FI_FSize] = (fldsize*0.67).round if fldvsize>25
              end
              fldvsize = field[FI_FSize].to_i if field[FI_FSize]
              if (fldvsize <= 0) or ((fldvsize > fldsize) and (fldsize>0))
                fldvsize = (fldsize*0.67).round if (fldsize>0) and (fldvsize>30)
                fldvsize = 120 if fldvsize>120
              end
              indd, lab_or, new_row = decode_pos(field[FI_Pos])
              plus = (indd and (indd[0, 1]=='+'))
              indd = indd[1..-1] if plus
              if indd and (indd.size>0)
                indd = indd.to_f
              else
                indd = nil
              end
              ind = 0.0
              if not indd
                last_ind += 1.0
                ind = last_ind
              else
                if plus
                  last_ind += indd
                  ind = last_ind
                else
                  ind = indd
                  last_ind += indd if indd < 200  # matter fileds have index lower then 200
                end
              end
              field[FI_Size] = fldsize
              field[FI_VFName] = field_title(field)
              field[FI_Index] = ind
              field[FI_LabOr] = lab_or
              field[FI_NewRow] = new_row
              field[FI_VFSize] = fldvsize
              #p '[field[FI_VFName], field[FI_View]]='+[field[FI_VFName], field[FI_View]].inspect
            end
            df.sort! {|a,b| a[FI_Index]<=>b[FI_Index] }
          end
          #i = tab_fields.index{ |tf| tf[0]=='panhash'}
          #@panhash_ind = i if i
          #i = tab_fields.index{ |tf| tf[0]=='modified'}
          #@modified_ind = i if i
          @def_fields = df
        end
      end
      def def_hash(fd)
        len = 0
        hash = ''
        if (fd.is_a? Array) and fd[FI_Type]
          case fd[FI_Type].to_s
            when 'Integer', 'Time', 'Coord'
              hash = 'integer'
              len = 4
            when 'Byte'
              hash = 'byte'
              len = 1
            when 'Word'
              hash = 'word'
              len = 2
            when 'Date'
              hash = 'date'
              len = 3
            else
              hash = 'hash'
              len = fd[FI_Size]
              len = 4 if (not len.is_a? Integer) or (len>4)
          end
        end
        [len, hash]
      end
      def panhash_pattern(auto_calc=true)
        res = []
        last_ind = 0
        def_flds = def_fields
        if def_flds
          def_flds.each do |e|
            if (e.is_a? Array) and e[FI_Hash] and (e[FI_Hash].to_s != '')
              hash = e[FI_Hash]
              #p 'hash='+hash.inspect
              ind = 0
              len = 0
              i = hash.index(':')
              if i
                ind = hash[0, i].to_i
                hash = hash[i+1..-1]
              end
              i = hash.index('(')
              if i
                len = hash[i+1..-1]
                len = len[0..-2] if len[-1]==')'
                len = len.to_i
                hash = hash[0, i]
              end
              #p '@@@[ind, hash, len]='+[ind, hash, len].inspect
              if (not hash) or (hash=='') or (len<=0)
                dlen, dhash = def_hash(e)
                #p '[hash, len, dhash, dlen]='+[hash, len, dhash, dlen].inspect
                hash = dhash if (not hash) or (hash=='')
                if len<=0
                  case hash
                    when 'byte', 'lang'
                      len = 1
                    when 'date'
                      len = 3
                    when 'crc16', 'word'
                      len = 2
                    when 'crc32', 'integer', 'time'
                      len = 4
                  end
                end
                len = dlen if len<=0
                #p '=[hash, len]='+[hash, len].inspect
              end
              ind = last_ind + 1 if ind==0
              res << [ind, e[FI_Id], hash, len]
              last_ind = ind
            end
          end
        end
        #p 'res='+res.inspect
        if res==[]
          parent = get_parent
          if parent
            res = parent.panhash_pattern(false)
          end
        else
          res.sort! { |a,b| a[0]<=>b[0] }  # sort formula by index
          res.collect! { |e| [e[1],e[2],e[3]] }  # delete sort index (id, hash, len)
        end
        if auto_calc
          if ((not res) or (res == [])) and (def_flds.is_a? Array)
            # panhash formula is not defined
            res = []
            used_len = 0
            nil_count = 0
            last_nil = 0
            max_i = def_flds.count
            i = 0
            while (i<max_i) and (used_len<$max_hash_len)
              e = def_flds[i]
              if e[FI_Id] != 'panhash'
                len, hash = def_hash(e)
                res << [e[FI_Id], hash, len]
                if len>0
                  used_len += len
                else
                  nil_count += 1
                  last_nil = res.size-1
                end
              end
              i += 1
            end
            if used_len<$max_hash_len
              mid_len = 0
              mid_len = ($max_hash_len-used_len)/nil_count if nil_count>0
              if mid_len>0
                tail = 20
                res.each_with_index do |e,i|
                  if (e[2]<=0)
                    if (i==last_nil)
                      e[2]=tail
                     used_len += tail
                    else
                      e[2]=mid_len
                      used_len += mid_len
                    end
                  end
                  tail -= e[2]
                end
              end
            end
            res.delete_if {|e| (not e[2].is_a? Integer) or (e[2]==0) }
            i = res.count-1
            while (i>0) and (used_len > $max_hash_len)
              used_len -= res[i][2]
              i -= 1
            end
            res = res[0, i+1]
          end
        end
        #p 'pan_pattern='+res.inspect
        res
      end
      def def_fields=(x)
        @def_fields = x
      end
      def tables
        @tables
      end
      def tables=(x)
        @tables = x
      end
      def name
        @name
      end
      def name=(x)
        @name = x
      end
      def repositories
        $repositories
      end
    end
    def initialize(*args)
      super(*args)
      self.class.expand_def_fields_to_parent
    end
    def ider
      self.class.ider
    end
    def ider=(x)
      self.class.ider = x
    end
    def kind
      self.class.kind
    end
    def kind=(x)
      self.class.kind = x
    end
    def sort
      self.class.sort
    end
    def sort=(x)
      self.class.sort = x
    end
    #def lang
    #  self.class.lang
    #end
    #def lang=(x)
    #  self.class.lang = x
    #end
    def def_fields
      self.class.def_fields
    end
    def def_fields=(x)
      self.class.def_fields = x
    end
    def tables
      self.class.tables
    end
    def tables=(x)
      self.class.tables = x
    end
    def name
      self.class.name
    end
    def name=(x)
      self.class.name = x
    end
    def repositories
      $repositories
    end
    def sname
      _(PandoraKernel.get_name_or_names(name))
    end
    def pname
      _(PandoraKernel.get_name_or_names(name, true))
    end
    attr_accessor :namesvalues
    def tab_fields
      self.class.tab_fields
    end
    def select(afilter=nil, set_namesvalues=false, fields=nil, sort=nil, limit=nil)
      res = self.class.repositories.get_tab_select(self, self.class.tables[0], afilter, fields, sort, limit)
      if set_namesvalues and res[0].is_a? Array
        @namesvalues = {}
        tab_fields.each_with_index do |td, i|
          namesvalues[td[TI_Name]] = res[0][i]
        end
      end
      res
    end
    def update(values, names=nil, filter='', set_namesvalues=false)
      if values.is_a? Hash
        names = values.keys
        values = values.values
        #p 'update names='+names.inspect
        #p 'update values='+values.inspect
      end
      res = self.class.repositories.get_tab_update(self, self.class.tables[0], values, names, filter)
      if set_namesvalues and res
        @namesvalues = {}
        values.each_with_index do |v, i|
          namesvalues[names[i]] = v
        end
      end
      res
    end
    def field_val(fld_name, values)
      res = nil
      if values.is_a? Array
        i = tab_fields.index{ |tf| tf[0]==fld_name}
        res = values[i] if i
      end
      res
    end
    def field_des(fld_name)
      self.class.field_des(fld_name)
    end
    def field_title(fd)
      self.class.field_title(fd)
    end
    def panhash_pattern
      if not @panhash_pattern
        @panhash_pattern = self.class.panhash_pattern
      end
      @panhash_pattern
    end
    def lang_to_str(lang)
      case lang
        when 0
          _('any')
        when 1
          _('eng')
        when 5
          _('rus')
        else
          _('lang')
      end
    end
    def panhash_formula
      res = ''
      pp = panhash_pattern
      if pp.is_a? Array
        #ppn = pp.collect{|p| field_title(p[0]).gsub(' ', '.') }
        flddes = def_fields
        # ids and names on current language for all fields
        fldtits = flddes.collect do |fd|
          id = fd[FI_Id]
          tit = field_title(fd)    #.gsub(' ', '.')
          [id, tit]
        end
        #p '[fldtits,pp]='+[fldtits,pp].inspect
        # to receive restricted names
        ppr = []
        pp.each_with_index do |p,i|
          n = nil
          j = fldtits.index {|ft| ft[0]==p[0]}
          n = fldtits[j][1] if j
          if n.is_a? String
            s = 1
            found = false
            while (s<8) and (s<n.size) and not found
              nr = n[0,s]
              equaled = fldtits.select { |ft| ft[1][0,s]==nr  }
              found = equaled.count<=1
              s += 1
            end
            nr = n[0, 8] if not found
            ppr[i] = nr
          else
            ppr[i] = n.to_s
          end
        end
        # compose panhash mask
        siz = 2
        pp.each_with_index do |hp,i|
          res << '/' if res != ''
          res << ppr[i]+':'+hp[2].to_s
          siz += hp[2].to_i
        end
        kn = ider.downcase
        res = 'pandora:' + kn + '/' + res + ' =' + siz.to_s
      end
      res
    end
    def calc_hash(hfor, hlen, fval)
      res = nil
      #fval = [fval].pack('C*') if fval.is_a? Fixnum
      #p 'fval='+fval.inspect+'  hfor='+hfor.inspect
      if fval and (not (fval.is_a? String) or (fval != ''))
        #p 'fval='+fval.inspect+'  hfor='+hfor.inspect
        hfor = 'integer' if (not hfor or hfor=='') and (fval.is_a? Integer)
        hfor = 'hash' if ((hfor=='') or (hfor=='text')) and (fval.is_a? String) and (fval.size>20)
        if ['integer', 'word', 'byte', 'lang'].include? hfor
          if not (fval.is_a? Integer)
            fval = fval.to_i
          end
          res = fval
        elsif hfor == 'date'
          #dmy = fval.split('.')   # D.M.Y
          # convert DMY to time from 1970 in days
          #p "date="+[dmy[2].to_i, dmy[1].to_i, dmy[0].to_i].inspect
          #p Time.now.to_a.inspect

          #vals = Time.now.to_a
          #y, m, d = [vals[5], vals[4], vals[3]]  #current day
          #p [y, m, d]
          #expire = Time.local(y+5, m, d)
          #p expire
          #p '-------'
          #p [dmy[2].to_i, dmy[1].to_i, dmy[0].to_i]

          #res = Time.local(dmy[2].to_i, dmy[1].to_i, dmy[0].to_i)
          #p res
          res = 0
          if fval.is_a? Integer
            res = Time.at(fval)
          else
            res = Time.parse(fval)
          end
          res = res.to_i / (24*60*60)
          # convert date to 0 year epoch
          res += (1970-1900)*365
          #p res.to_s(16)
          #res = [t].pack('N')
        else
          if fval.is_a? Integer
            fval = PandoraKernel.bigint_to_bytes(fval)
          elsif fval.is_a? Float
            fval = fval.to_s
          end
          case hfor
            when 'sha1', 'hash'
              res = AsciiString.new
              #res = ''
              #res.force_encoding('ASCII-8BIT')
              res << Digest::SHA1.digest(fval)
            when 'phash'
              res = fval[2..-1]
            when 'md5'
              res = AsciiString.new
              #res = ''
              #res.force_encoding('ASCII-8BIT')
              res << Digest::MD5.digest(fval)
            when 'crc16'
              res = Zlib.crc32(fval) #if fval.is_a? String
              res = (res & 0xFFFF) ^ (res >> 16)
            when 'crc32'
              res = Zlib.crc32(fval) #if fval.is_a? String
            when 'raw'
              res = AsciiString.new(fval)
          end
        end
        if not res
          if fval.is_a? String
            res = AsciiString.new(fval)
            #res = ''
            #res.force_encoding('ASCII-8BIT')
          else
            res = fval
          end
        end
        if res.is_a? Integer
          res = AsciiString.new(PandoraKernel.bigint_to_bytes(res))
          #p '---- '+hlen.to_s
          #p PandoraKernel.bytes_to_hex(res)

          res = PandoraKernel.fill_zeros_from_left(res, hlen)
          #p PandoraKernel.bytes_to_hex(res)
          #p res = res[-hlen..-1]  # trunc if big
        elsif not fval.is_a? String
          res = AsciiString.new(res.to_s)
          #res << res.to_s
          #res.force_encoding('ASCII-8BIT')
        end
        res = AsciiString.new(res[0, hlen])
      end
      if not res
        res = AsciiString.new
        #res = ''
        #res.force_encoding('ASCII-8BIT')
        res << [0].pack('C')
      end
      while res.size<hlen
        res << [0].pack('C')
      end
      #p 'hash='+res.to_s
      #p 'hex_of_str='+hex_of_str(res)
      #res.force_encoding('ASCII-8BIT')
      res = AsciiString.new(res)
    end
    def show_panhash(val, prefix=true)
      res = ''
      if prefix
        res = PandoraKernel.bytes_to_hex(val[0,2])+' '
        val = val[2..-1]
      end
      res2 = PandoraKernel.bytes_to_hex(val)
      i = 0
      panhash_pattern.each do |pp|
        if (i>0) and (i<res2.size)
          res2 = res2[0, i] + ' ' + res2[i..-1]
          i += 1
        end
        i += pp[2] * 2
      end
      res << res2
    end
    def panhash(values, lang=0, prefix=true, hexview=false)
      res = AsciiString.new
      if prefix
        res << [kind,lang].pack('CC')
      end
      if values.is_a? Hash
        values0 = values
        values = {}
        values0.each {|k,v| values[k.to_s] = v}  # sym key to string key
      end
      pattern = panhash_pattern
      pattern.each_with_index do |pat, ind|
        fname = pat[0]
        fval = nil
        if values.is_a? Hash
          fval = values[fname]
        else
          fval = field_val(fname, values)
        end
        hfor  = pat[1]
        hlen  = pat[2]
        #p '[fval, fname, values]='+[fval, fname, values].inspect
        #p '[hfor, hlen, fval]='+[hfor, hlen, fval].inspect
        #res.force_encoding('ASCII-8BIT')
        res << AsciiString.new(calc_hash(hfor, hlen, fval))
      end
      res = AsciiString.new(res)
      res = show_panhash(res, prefix) if hexview
      res
    end
    def matter_fields
      res = {}
      if namesvalues.is_a? Hash
        panhash_pattern.each do |pat|
          fname = pat[0]
          if fname
            fval = namesvalues[fname]
            res[fname] = fval
          end
        end
      end
      res
    end
    def clear_excess_fields(row)
      #row.delete_at(0)
      #row.delete_at(self.class.panhash_ind) if self.class.panhash_ind
      #row.delete_at(self.class.modified_ind) if self.class.modified_ind
      #row
      res = {}
      if namesvalues.is_a? Hash
        namesvalues.each do |k, v|
          if not (['id', 'panhash', 'modified'].include? k)
            res[k] = v
          end
        end
      end
      res
    end
  end

end

# ==============================================================================
# == Pandora logic model
# == RU: Логическая модель Пандора
module PandoraModel

  include PandoraKernel

  PF_Name    = 0
  PF_Desc    = 1
  PF_Type    = 2
  PF_Section = 3
  PF_Setting = 4

  # Pandora's object
  # RU: Объект Пандоры
  class Panobject < PandoraKernel::BasePanobject
    ider = 'Panobject'
    name = "Объект Пандоры"
  end

  $panobject_list = []

  # Compose pandora model definition from XML file
  # RU: Сформировать описание модели по XML-файлу
  def self.load_model_from_xml(lang='ru')
    lang = '.'+lang
    #dir_mask = File.join(File.join($pandora_model_dir, '**'), '*.xml')
    dir_mask = File.join($pandora_model_dir, '*.xml')
    dir_list = Dir.glob(dir_mask).sort
    dir_list.each do |pathfilename|
      filename = File.basename(pathfilename)
      file = Object::File.open(pathfilename)
      xml_doc = REXML::Document.new(file)
      xml_doc.elements.each('pandora-model/*') do |section|
        if section.name != 'Defaults'
          # Field definition
          section.elements.each('*') do |element|
            panobj_id = element.name
            #p 'panobj_id='+panobj_id.inspect
            new_panobj = true
            flds = []
            panobject_class = nil
            panobject_class = PandoraModel.const_get(panobj_id) if PandoraModel.const_defined? panobj_id
            #p panobject_class
            if panobject_class and panobject_class.def_fields and (panobject_class.def_fields != [])
              # just extend existed class
              panobj_name = panobject_class.name
              panobj_tabl = panobject_class.tables
              new_panobj = false
              #p 'old='+panobject_class.inspect
            else
              # create new class
              panobj_name = panobj_id
              if not panobject_class #not PandoraModel.const_defined? panobj_id
                parent_class = element.attributes['parent']
                if (not parent_class) or (parent_class=='') or (not (PandoraModel.const_defined? parent_class))
                  if parent_class
                    puts _('Parent is not defined, ignored')+' /'+filename+':'+panobj_id+'<'+parent_class
                  end
                  parent_class = 'Panobject'
                end
                if PandoraModel.const_defined? parent_class
                  PandoraModel.const_get(parent_class).def_fields.each do |f|
                    flds << f.dup
                  end
                end
                init_code = 'class '+panobj_id+' < PandoraModel::'+parent_class+'; name = "'+panobj_name+'"; end'
                module_eval(init_code)
                panobject_class = PandoraModel.const_get(panobj_id)
                $panobject_list << panobject_class if not $panobject_list.include? panobject_class
              end

              #p 'new='+panobject_class.inspect
              panobject_class.def_fields = flds
              panobject_class.ider = panobj_id
              kind = panobject_class.superclass.kind #if panobject_class.superclass <= BasePanobject
              kind ||= 0
              panobject_class.kind = kind
              #panobject_class.lang = 5
              panobj_tabl = panobj_id
              panobj_tabl = PandoraKernel::get_name_or_names(panobj_tabl, true)
              panobj_tabl.downcase!
              panobject_class.tables = [['robux', panobj_tabl], ['perm', panobj_tabl]]
            end
            panobj_kind = element.attributes['kind']
            panobject_class.kind = panobj_kind.to_i if panobj_kind
            panobj_sort = element.attributes['sort']
            panobject_class.sort = panobj_sort if panobj_sort
            flds = panobject_class.def_fields
            flds ||= []
            #p 'flds='+flds.inspect
            panobj_name_en = element.attributes['name']
            panobj_name = panobj_name_en if (panobj_name==panobj_id) and panobj_name_en and (panobj_name_en != '')
            panobj_name_lang = element.attributes['name'+lang]
            panobj_name = panobj_name_lang if panobj_name_lang and (panobj_name_lang != '')
            #puts panobj_id+'=['+panobj_name+']'
            panobject_class.name = panobj_name

            panobj_tabl = element.attributes['table']
            panobject_class.tables = [['robux', panobj_tabl], ['perm', panobj_tabl]] if panobj_tabl

            # fill fields
            element.elements.each('*') do |sub_elem|
              seu = sub_elem.name.upcase
              if seu==sub_elem.name  #elem name has BIG latters
                # This is a function
                #p 'Функция не определена: ['+sub_elem.name+']'
              else
                # This is a field
                i = 0
                while (i<flds.size) and (flds[i][FI_Id] != sub_elem.name) do i+=1 end
                fld_exists = (i<flds.size)
                if new_panobj or fld_exists
                  # new panobject or field exists already
                  if fld_exists
                    fld_name = flds[i][FI_Name]
                  else
                    flds[i] = []
                    flds[i][FI_Id] = sub_elem.name
                    fld_name = sub_elem.name
                  end
                  fld_name = sub_elem.attributes['name']
                  flds[i][FI_Name] = fld_name if fld_name and (fld_name != '')
                  #fld_name = fld_name_en if (fld_name_en ) and (fld_name_en != '')
                  fld_name_lang = sub_elem.attributes['name'+lang]
                  flds[i][FI_LName] = fld_name_lang if fld_name_lang and (fld_name_lang != '')
                  #fld_name = fld_name_lang if (fld_name_lang ) and (fld_name_lang != '')
                  #flds[i][FI_Name] = fld_name

                  fld_type = sub_elem.attributes['type']
                  flds[i][FI_Type] = fld_type if fld_type and (fld_type != '')
                  fld_size = sub_elem.attributes['size']
                  flds[i][FI_Size] = fld_size if fld_size and (fld_size != '')
                  fld_pos = sub_elem.attributes['pos']
                  flds[i][FI_Pos] = fld_pos if fld_pos and (fld_pos != '')
                  fld_fsize = sub_elem.attributes['fsize']
                  flds[i][FI_FSize] = fld_fsize.to_i if fld_fsize and (fld_fsize != '')

                  fld_hash = sub_elem.attributes['hash']
                  flds[i][FI_Hash] = fld_hash if fld_hash and (fld_hash != '')

                  fld_view = sub_elem.attributes['view']
                  flds[i][FI_View] = fld_view if fld_view and (fld_view != '')
                else
                  # not new panobject, field doesn't exists
                  puts _('Property was not defined, ignored')+' /'+filename+':'+panobj_id+'.'+sub_elem.name
                end
              end
            end
            #p flds
            #p "========"
            panobject_class.def_fields = flds
          end
        else
          # Default param values
          section.elements.each('*') do |element|
            name = element.name
            desc = element.attributes['desc']
            desc ||= name
            type = element.attributes['type']
            section = element.attributes['section']
            setting = element.attributes['setting']
            row = nil
            ind = $pandora_parameters.index{ |row| row[PF_Name]==name }
            if ind
              row = $pandora_parameters[ind]
            else
              row = []
              row[PF_Name] = name
              $pandora_parameters << row
              ind = $pandora_parameters.size-1
            end
            row[PF_Desc] = desc if desc
            row[PF_Type] = type if type
            row[PF_Section] = section if section
            row[PF_Setting] = setting if setting
            $pandora_parameters[ind] = row
          end
        end
      end
      file.close
    end
  end

  def self.panobjectclass_by_kind(kind)
    res = nil
    if kind>0
      $panobject_list.each do |panobject_class|
        if panobject_class.kind==kind
          res = panobject_class
          break
        end
      end
    end
    res
  end

end

# ==============================================================================
# == Graphical user interface of Pandora
# == RU: Графический интерфейс Пандора
module PandoraGUI
  include PandoraKernel
  include PandoraModel

  if not $gtk2_on
    puts "Gtk не установлена"
  end

  # About dialog hooks
  # RU: Обработчики диалога "О программе"
  Gtk::AboutDialog.set_url_hook do |about, link|
    if os_family=='windows' then a1='start'; a2='' else a1='xdg-open'; a2=' &' end;
    system(a1+' '+link+a2)
  end
  Gtk::AboutDialog.set_email_hook do |about, link|
    if os_family=='windows' then a1='start'; a2='' else a1='xdg-email'; a2=' &' end;
    system(a1+' '+link+a2)
  end

  # Show About dialog
  # RU: Показ окна "О программе"
  def self.show_about
    dlg = Gtk::AboutDialog.new
    dlg.transient_for = $window
    dlg.icon = $window.icon
    dlg.name = $window.title
    dlg.version = "0.1"
    dlg.logo = Gdk::Pixbuf.new(File.join($pandora_view_dir, 'pandora.png'))
    dlg.authors = [_('Michael Galyuk')+' <robux@mail.ru>']
    dlg.artists = ['© '+_('Rights to logo are owned by 21th Century Fox')]
    dlg.comments = _('Distributed Social Network')
    dlg.copyright = _('Free software')+' 2012, '+_('Michael Galyuk')
    begin
      file = File.open(File.join($pandora_root_dir, 'LICENSE.TXT'), 'r')
      gpl_text = '================='+_('Full text')+" LICENSE.TXT==================\n"+file.read
      file.close
    rescue
      gpl_text = _('Full text is in the file')+' LICENSE.TXT.'
    end
    dlg.license = _("Pandora is licensed under GNU GPLv2.\n"+
      "\nFundamentals:\n"+
      "- program code is open, distributed free and without warranty;\n"+
      "- author does not require you money, but demands respect authorship;\n"+
      "- you can change the code, sent to the authors for inclusion in the next release;\n"+
      "- your own release you must distribute with another name and only licensed under GPL;\n"+
      "- if you do not understand the GPL or disagree with it, you have to uninstall the program.\n\n")+gpl_text
    dlg.website = 'https://github.com/Novator/Pandora'
    #if os_family=='unix'
      dlg.program_name = dlg.name
      dlg.skip_taskbar_hint = true
    #end
    dlg.run
    dlg.destroy
    $window.present
  end

  $statusbar = nil

  def self.set_statusbar_text(statusbar, text)
    statusbar.pop(0)
    statusbar.push(0, text)
  end

  # Advanced dialog window
  # RU: Продвинутое окно диалога
  class AdvancedDialog < Gtk::Window
    attr_accessor :response, :window, :notebook, :vpaned, :viewport, :hbox, :enter_like_tab, :enter_like_ok, \
      :panelbox, :okbutton, :cancelbutton, :def_widget

    def initialize(*args)
      super(*args)
      @response = 0
      @window = self
      @enter_like_tab = false
      @enter_like_ok = true
      set_default_size(300, -1)

      window.transient_for = $window
      window.modal = true
      #window.skip_taskbar_hint = true
      window.window_position = Gtk::Window::POS_CENTER
      #window.type_hint = Gdk::Window::TYPE_HINT_DIALOG

      @vpaned = Gtk::VPaned.new
      vpaned.border_width = 2
      window.add(vpaned)

      sw = Gtk::ScrolledWindow.new(nil, nil)
      sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      @viewport = Gtk::Viewport.new(nil, nil)
      sw.add(viewport)

      image = Gtk::Image.new(Gtk::Stock::PROPERTIES, Gtk::IconSize::MENU)
      image.set_padding(2, 0)
      label_box1 = TabLabelBox.new(image, _('Basic'), nil, false, 0)

      @notebook = Gtk::Notebook.new
      page = notebook.append_page(sw, label_box1)
      vpaned.pack1(notebook, true, true)

      @panelbox = Gtk::VBox.new
      @hbox = Gtk::HBox.new
      panelbox.pack_start(hbox, false, false, 0)

      vpaned.pack2(panelbox, false, true)

      bbox = Gtk::HBox.new
      bbox.border_width = 2
      bbox.spacing = 4

      @okbutton = Gtk::Button.new(Gtk::Stock::OK)
      okbutton.width_request = 110
      okbutton.signal_connect('clicked') { |*args| @response=1 }
      bbox.pack_start(okbutton, false, false, 0)

      @cancelbutton = Gtk::Button.new(Gtk::Stock::CANCEL)
      cancelbutton.width_request = 110
      cancelbutton.signal_connect('clicked') { |*args| @response=2 }
      bbox.pack_start(cancelbutton, false, false, 0)

      hbox.pack_start(bbox, true, false, 1.0)

      window.signal_connect('delete-event') { |*args|
        @response=2
        false
      }
      window.signal_connect('destroy') { |*args| @response=2 }

      window.signal_connect('key_press_event') do |widget, event|
        if (event.keyval==Gdk::Keyval::GDK_Tab) and enter_like_tab  # Enter works like Tab
          event.hardware_keycode=23
          event.keyval=Gdk::Keyval::GDK_Tab
          window.signal_emit('key-press-event', event)
          true
        elsif
          [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval) \
          and (event.state.control_mask? or (enter_like_ok and (not (self.focus.is_a? Gtk::TextView))))
        then
          #p "=-=-=-"
          #p self.focus
          #p self.focus.is_a? Gtk::TextView
          okbutton.activate
          true
        elsif (event.keyval==Gdk::Keyval::GDK_Escape) or \
          ([Gdk::Keyval::GDK_w, Gdk::Keyval::GDK_W, 1731, 1763].include?(event.keyval) and event.state.control_mask?) #w, W, ц, Ц
        then
          cancelbutton.activate
          false
        elsif ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?(event.keyval) and event.state.mod1_mask?) or
          ([Gdk::Keyval::GDK_q, Gdk::Keyval::GDK_Q, 1738, 1770].include?(event.keyval) and event.state.control_mask?) #q, Q, й, Й
        then
          $window.destroy
          @response=2
          false
        else
          false
        end
      end
    end

    # show dialog until key pressed
    def run(alien_thread=false)
      res = false
      show_all
      if @def_widget
        #focus = @def_widget
        @def_widget.grab_focus
      end
      while (not destroyed?) and (@response == 0) do
        unless alien_thread
          Gtk.main_iteration
        end
        Thread.pass
      end
      if not destroyed?
        if (@response==1)
          yield(@response) if block_given?
          res = true
        end
        self.destroy
      end
      res
    end
  end

  # ToggleToolButton with safety "active" switching
  # ToggleToolButton с безопасным переключением "active"
  class GoodToggleToolButton < Gtk::ToggleToolButton
    def good_signal_clicked
      @clicked_signal = self.signal_connect('clicked') do |*args|
        yield(*args) if block_given?
      end
    end
    def good_set_active(an_active)
      if @clicked_signal
        self.signal_handler_block(@clicked_signal) do
          self.active = an_active
        end
      end
    end
  end

  # Add button to toolbar
  # RU: Добавить кнопку на панель инструментов
  def self.add_tool_btn(toolbar, stock, title, toggle=nil)
    btn = nil
    if toggle != nil
      btn = GoodToggleToolButton.new(stock)
      btn.good_signal_clicked do |*args|
        yield(*args) if block_given?
      end
      btn.active = toggle if toggle
    else
      image = Gtk::Image.new(stock, Gtk::IconSize::MENU)
      btn = Gtk::ToolButton.new(image, _(title))
      btn.signal_connect('clicked') do |*args|
        yield(*args) if block_given?
      end
    end
    new_api = false
    begin
      btn.tooltip_text = btn.label
      new_api = true
    rescue
    end
    if new_api
      toolbar.add(btn)
    else
      toolbar.append(btn, btn.label, btn.label)
    end
    btn
  end

  # Entry with allowed symbols of mask
  # RU: Поле ввода с допустимыми символами в маске
  class MaskEntry < Gtk::Entry
    attr_accessor :mask
    def initialize
      super
      @mask_key_press_event = signal_connect('key_press_event') do |widget, event|
        res = false
        if (event.keyval<60000) and (mask.is_a? String) and (mask.size>0)
          res = (not mask.include?(event.keyval.chr))
        end
        res
      end
    end
  end

  class IntegerEntry < MaskEntry
    def initialize
      super
      @mask = '0123456789-'
    end
  end

  class FloatEntry < MaskEntry
    def initialize
      super
      @mask = '0123456789.-e'
    end
  end

  class HexEntry < MaskEntry
    def initialize
      super
      @mask = '0123456789abcdefABCDEF'
    end
  end

  # Dialog with enter fields
  # RU: Диалог с полями ввода
  class FieldsDialog < AdvancedDialog
    include PandoraKernel

    attr_accessor :panobject, :fields, :text_fields, :toolbar, :toolbar2, :statusbar, \
      :support_btn, :vouch_btn, :trust_scale, :trust0, :public_btn, :lang_entry, :format, :view_buffer

    def add_menu_item(label, menu, text)
      mi = Gtk::MenuItem.new(text)
      menu.append(mi)
      mi.signal_connect('activate') { |mi|
        label.label = mi.label
        @format = mi.label.to_s
        p 'format changed to: '+format.to_s
      }
    end

    def set_view_buffer(format, view_buffer, raw_buffer)
      view_buffer.text = raw_buffer.text
    end

    def set_raw_buffer(format, raw_buffer, view_buffer)
      raw_buffer.text = view_buffer.text
    end

    def set_buffers(init=false)
      child = notebook.get_nth_page(notebook.page)
      if (child.is_a? Gtk::ScrolledWindow) and (child.children[0].is_a? Gtk::TextView)
        tv = child.children[0]
        if init or not @raw_buffer
          @raw_buffer = tv.buffer
        end
        if @view_mode
          tv.buffer = @view_buffer if tv.buffer != @view_buffer
        elsif tv.buffer != @raw_buffer
          tv.buffer = @raw_buffer
        end

        if @view_mode
          set_view_buffer(format, @view_buffer, @raw_buffer)
        else
          set_raw_buffer(format, @raw_buffer, @view_buffer)
        end
      end
    end

    def set_tag(tag)
      if tag
        child = notebook.get_nth_page(notebook.page)
        if (child.is_a? Gtk::ScrolledWindow) and (child.children[0].is_a? Gtk::TextView)
          tv = child.children[0]
          buffer = tv.buffer

          if @view_buffer==buffer
            bounds = buffer.selection_bounds
            @view_buffer.apply_tag(tag, bounds[0], bounds[1])
          else
            bounds = buffer.selection_bounds
            ltext = rtext = ''
            case tag
              when 'bold'
                ltext = rtext = '*'
              when 'italic'
                ltext = rtext = '/'
              when 'strike'
                ltext = rtext = '-'
              when 'undline'
                ltext = rtext = '_'
            end
            lpos = bounds[0].offset
            rpos = bounds[1].offset
            if ltext != ''
              @raw_buffer.insert(@raw_buffer.get_iter_at_offset(lpos), ltext)
              lpos += ltext.length
              rpos += ltext.length
            end
            if rtext != ''
              @raw_buffer.insert(@raw_buffer.get_iter_at_offset(rpos), rtext)
            end
            p [lpos, rpos]
            #buffer.selection_bounds = [bounds[0], rpos]
            @raw_buffer.move_mark('selection_bound', @raw_buffer.get_iter_at_offset(lpos))
            @raw_buffer.move_mark('insert', @raw_buffer.get_iter_at_offset(rpos))
            #@raw_buffer.get_iter_at_offset(0)
          end
        end
      end
    end

    def initialize(apanobject, afields=[], *args)
      super(*args)
      @panobject = apanobject
      @fields = afields

      window.signal_connect('configure-event') do |widget, event|
        window.on_resize_window(widget, event)
        false
      end

      @toolbar = Gtk::Toolbar.new
      toolbar.toolbar_style = Gtk::Toolbar::Style::ICONS
      panelbox.pack_start(toolbar, false, false, 0)

      @toolbar2 = Gtk::Toolbar.new
      toolbar2.toolbar_style = Gtk::Toolbar::Style::ICONS
      panelbox.pack_start(toolbar2, false, false, 0)

      @raw_buffer = nil
      @view_mode = true
      @view_buffer = Gtk::TextBuffer.new
      @view_buffer.create_tag('bold', 'weight' => Pango::FontDescription::WEIGHT_BOLD)
      @view_buffer.create_tag('italic', 'style' => Pango::FontDescription::STYLE_ITALIC)
      @view_buffer.create_tag('strike', 'strikethrough' => true)
      @view_buffer.create_tag('undline', 'underline' => Pango::AttrUnderline::SINGLE)
      @view_buffer.create_tag('dundline', 'underline' => Pango::AttrUnderline::DOUBLE)
      @view_buffer.create_tag('link', {'foreground' => 'blue', 'underline' => Pango::AttrUnderline::SINGLE})
      @view_buffer.create_tag('linked', {'foreground' => 'navy', 'underline' => Pango::AttrUnderline::SINGLE})
      @view_buffer.create_tag('left', 'justification' => Gtk::JUSTIFY_LEFT)
      @view_buffer.create_tag('center', 'justification' => Gtk::JUSTIFY_CENTER)
      @view_buffer.create_tag('right', 'justification' => Gtk::JUSTIFY_RIGHT)
      @view_buffer.create_tag('fill', 'justification' => Gtk::JUSTIFY_FILL)

      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::DND, 'Type', true) do |btn|
        @view_mode = btn.active?
        set_buffers
      end

      btn = Gtk::MenuToolButton.new(nil, 'auto')
      menu = Gtk::Menu.new
      btn.menu = menu
      add_menu_item(btn, menu, 'auto')
      add_menu_item(btn, menu, 'plain')
      add_menu_item(btn, menu, 'org-mode')
      add_menu_item(btn, menu, 'bbcode')
      add_menu_item(btn, menu, 'wiki')
      add_menu_item(btn, menu, 'html')
      add_menu_item(btn, menu, 'ruby')
      add_menu_item(btn, menu, 'python')
      add_menu_item(btn, menu, 'xml')
      menu.show_all
      toolbar.add(btn)

      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::BOLD, 'Bold') do |*args|
        set_tag('bold')
      end
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::ITALIC, 'Italic') do |*args|
        set_tag('italic')
      end
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::STRIKETHROUGH, 'Strike') do |*args|
        set_tag('strike')
      end
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::UNDERLINE, 'Underline') do |*args|
        set_tag('undline')
      end
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::UNDO, 'Undo')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::REDO, 'Redo')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::COPY, 'Copy')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::CUT, 'Cut')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::FIND, 'Find')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::JUSTIFY_LEFT, 'Left') do |*args|
        set_tag('left')
      end
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::JUSTIFY_RIGHT, 'Right') do |*args|
        set_tag('right')
      end
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::JUSTIFY_CENTER, 'Center') do |*args|
        set_tag('center')
      end
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::JUSTIFY_FILL, 'Fill') do |*args|
        set_tag('fill')
      end
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::SAVE, 'Save')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::OPEN, 'Open')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::JUMP_TO, 'Link') do |*args|
        set_tag('link')
      end
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::HOME, 'Image')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::OK, 'Ok') { |*args| @response=1 }
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::CANCEL, 'Cancel') { |*args| @response=2 }

      PandoraGUI.add_tool_btn(toolbar2, Gtk::Stock::ADD, 'Add')
      PandoraGUI.add_tool_btn(toolbar2, Gtk::Stock::DELETE, 'Delete')
      PandoraGUI.add_tool_btn(toolbar2, Gtk::Stock::OK, 'Ok') { |*args| @response=1 }
      PandoraGUI.add_tool_btn(toolbar2, Gtk::Stock::CANCEL, 'Cancel') { |*args| @response=2 }

      notebook.signal_connect('switch-page') do |widget, page, page_num|
        if page_num==0
          toolbar.hide
          toolbar2.hide
          hbox.show
        else
          child = notebook.get_nth_page(page_num)
          if (child.is_a? Gtk::ScrolledWindow) and (child.children[0].is_a? Gtk::TextView)
            toolbar2.hide
            hbox.hide
            toolbar.show
            set_buffers(true)
          else
            toolbar.hide
            hbox.hide
           toolbar2.show
          end
        end
      end

      @vbox = Gtk::VBox.new
      viewport.add(@vbox)

      @statusbar = Gtk::Statusbar.new
      PandoraGUI.set_statusbar_text(statusbar, '')
      statusbar.pack_start(Gtk::SeparatorToolItem.new, false, false, 0)
      panhash_btn = Gtk::Button.new(_('Panhash'))
      panhash_btn.relief = Gtk::RELIEF_NONE
      statusbar.pack_start(panhash_btn, false, false, 0)

      panelbox.pack_start(statusbar, false, false, 0)


      #rbvbox = Gtk::VBox.new

      @support_btn = Gtk::CheckButton.new(_('support'), true)
      #support_btn.signal_connect('toggled') do |widget|
      #  p "support"
      #end
      #rbvbox.pack_start(support_btn, false, false, 0)
      hbox.pack_start(support_btn, false, false, 0)

      trust_box = Gtk::VBox.new

      trust0 = nil
      @vouch_btn = Gtk::CheckButton.new(_('vouch'), true)
      vouch_btn.signal_connect('clicked') do |widget|
        if not widget.destroyed?
          if widget.inconsistent?
            if PandoraGUI.current_user_or_key(false)
              widget.inconsistent = false
              widget.active = true
              trust0 = 0.4
            end
          end
          trust_scale.sensitive = widget.active?
          if widget.active?
            trust0 ||= 0.4
            trust_scale.value = trust0
          else
            trust0 = trust_scale.value
          end
        end
      end
      trust_box.pack_start(vouch_btn, false, false, 0)

      #@scale_button = Gtk::ScaleButton.new(Gtk::IconSize::BUTTON)
      #@scale_button.set_icons(['gtk-goto-bottom', 'gtk-goto-top', 'gtk-execute'])
      #@scale_button.signal_connect('value-changed') { |widget, value| puts "value changed: #{value}" }

      tips = [_('villian'), _('destroyer'), _('dirty'), _('harmful'), _('bad'), _('vain'), \
        _('trying'), _('useful'), _('constructive'), _('creative'), _('genius')]

      #@trust ||= (127*0.4).round
      #val = trust/127.0
      adjustment = Gtk::Adjustment.new(0, -1.0, 1.0, 0.1, 0.3, 0)
      @trust_scale = Gtk::HScale.new(adjustment)
      trust_scale.set_size_request(140, -1)
      trust_scale.update_policy = Gtk::UPDATE_DELAYED
      trust_scale.digits = 1
      trust_scale.draw_value = true
      step = 254.fdiv(tips.size-1)
      trust_scale.signal_connect('value-changed') do |widget|
        #val = (widget.value*20).round/20.0
        val = widget.value
        #widget.value = val #if (val-widget.value).abs>0.05
        trust = (val*127).round
        #vouch_lab.text = sprintf('%2.1f', val) #trust.fdiv(127))
        r = 0
        g = 0
        b = 0
        if trust==0
          b = 40000
        else
          mul = ((trust.fdiv(127))*45000).round
          if trust>0
            g = mul+20000
          else
            r = -mul+20000
          end
        end
        tip = val.to_s
        color = Gdk::Color.new(r, g, b)
        widget.modify_fg(Gtk::STATE_NORMAL, color)
        @vouch_btn.modify_bg(Gtk::STATE_ACTIVE, color)
        i = ((trust+127)/step).round
        tip = tips[i]
        widget.tooltip_text = tip
      end
      #scale.signal_connect('change-value') do |widget|
      #  true
      #end
      trust_box.pack_start(trust_scale, false, false, 0)

      hbox.pack_start(trust_box, false, false, 0)

      public_box = Gtk::VBox.new

      @public_btn = Gtk::CheckButton.new(_('public'), true)
      public_btn.signal_connect('clicked') do |widget|
        if not widget.destroyed?
          if widget.inconsistent?
            if PandoraGUI.current_user_or_key(false)
              widget.inconsistent = false
              widget.active = true
            end
          end
        end
      end
      public_box.pack_start(public_btn, false, false, 0)

      #@lang_entry = Gtk::ComboBoxEntry.new(true)
      #lang_entry.set_size_request(60, 15)
      #lang_entry.append_text('0')
      #lang_entry.append_text('1')
      #lang_entry.append_text('5')

      @lang_entry = Gtk::Combo.new
      @lang_entry.set_popdown_strings(['0','1','5'])
      @lang_entry.entry.text = ''
      @lang_entry.entry.select_region(0, -1)
      @lang_entry.set_size_request(50, -1)
      public_box.pack_start(lang_entry, true, true, 5)

      hbox.pack_start(public_box, false, false, 0)

      #hbox.pack_start(rbvbox, false, false, 1.0)
      hbox.show_all

      bw,bh = hbox.size_request
      @btn_panel_height = bh

      # devide text fields in separate list
      @text_fields = []
      i = @fields.size
      while i>0 do
        i -= 1
        field = @fields[i]
        atext = field[FI_VFName]
        atype = field[FI_Type]
        if atype=='Text'
          image = Gtk::Image.new(Gtk::Stock::DND, Gtk::IconSize::MENU)
          image.set_padding(2, 0)
          textview = Gtk::TextView.new
          textview.wrap_mode = Gtk::TextTag::WRAP_WORD

          textview.signal_connect('key-press-event') do |widget, event|
            if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval) \
              and event.state.control_mask?
            then
              true
            end
          end

          textsw = Gtk::ScrolledWindow.new(nil, nil)
          textsw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
          textsw.add(textview)

          label_box = TabLabelBox.new(image, atext, nil, false, 0)
          page = notebook.append_page(textsw, label_box)

          textview.buffer.text = field[FI_Value].to_s
          field[FI_Widget] = textview

          txt_fld = field
          txt_fld << page
          @text_fields << txt_fld  #15??
          #@enter_like_ok = false

          @fields.delete_at(i)
        end
      end

      image = Gtk::Image.new(Gtk::Stock::INDEX, Gtk::IconSize::MENU)
      image.set_padding(2, 0)
      label_box2 = TabLabelBox.new(image, _('Relations'), nil, false, 0)
      sw = Gtk::ScrolledWindow.new(nil, nil)
      page = notebook.append_page(sw, label_box2)

      PandoraGUI.show_panobject_list(PandoraModel::Relation, nil, sw)


      image = Gtk::Image.new(Gtk::Stock::DIALOG_AUTHENTICATION, Gtk::IconSize::MENU)
      image.set_padding(2, 0)
      label_box2 = TabLabelBox.new(image, _('Signs'), nil, false, 0)
      sw = Gtk::ScrolledWindow.new(nil, nil)
      page = notebook.append_page(sw, label_box2)

      PandoraGUI.show_panobject_list(PandoraModel::Sign, nil, sw)

      image = Gtk::Image.new(Gtk::Stock::DIALOG_INFO, Gtk::IconSize::MENU)
      image.set_padding(2, 0)
      label_box2 = TabLabelBox.new(image, _('Opinions'), nil, false, 0)
      sw = Gtk::ScrolledWindow.new(nil, nil)
      page = notebook.append_page(sw, label_box2)

      PandoraGUI.show_panobject_list(PandoraModel::Opinion, nil, sw)

      # create labels, remember them, calc middle char width
      texts_width = 0
      texts_chars = 0
      labels_width = 0
      max_label_height = 0
      @fields.each do |field|
        atext = field[FI_VFName]
        label = Gtk::Label.new(atext)
        label.xalign = 0.0
        lw,lh = label.size_request
        field[FI_Label] = label
        field[FI_LabW] = lw
        field[FI_LabH] = lh
        texts_width += lw
        if $jcode_on
          texts_chars += atext.jlength
        else
          texts_chars += atext.length
        end
        #texts_chars += atext.length
        labels_width += lw
        max_label_height = lh if max_label_height < lh
      end
      @middle_char_width = texts_width.to_f / texts_chars

      # max window size
      scr = Gdk::Screen.default
      window_width, window_height = [scr.width-50, scr.height-100]
      form_width = window_width-36
      form_height = window_height-@btn_panel_height-55

      # compose first matrix, calc its geometry
      # create entries, set their widths/maxlen, remember them
      entries_width = 0
      max_entry_height = 0
      @def_widget = nil
      @fields.each do |field|
        #p 'field='+field.inspect
        max_size = 0
        fld_size = 0
        entry = Gtk::Entry.new
        @def_widget ||= entry
        begin
          atype = field[FI_Type]
          def_size = 10
          case atype
            when 'Integer'
              def_size = 10
            when 'String'
              def_size = 32
            when 'Blob'
              def_size = 128
          end
          #p '---'
          #p 'name='+field[FI_Name]
          #p 'atype='+atype.inspect
          #p 'def_size='+def_size.inspect
          fld_size = field[FI_FSize].to_i if field[FI_FSize]
          #p 'fld_size='+fld_size.inspect
          max_size = field[FI_Size].to_i
          fld_size = def_size if fld_size<=0
          max_size = fld_size if (max_size<fld_size) and (max_size>0)
          #p 'max_size='+max_size.inspect
        rescue
          #p 'FORM rescue [fld_size, max_size, def_size]='+[fld_size, max_size, def_size].inspect
          fld_size = def_size
        end
        #p 'Final [fld_size, max_size]='+[fld_size, max_size].inspect
        #entry.width_chars = fld_size
        entry.max_length = max_size
        color = field[FI_Color]
        if color
          color = Gdk::Color.parse(color)
        else
          color = $window.modifier_style.fg(Gtk::STATE_NORMAL)
        end
        #entry.modify_fg(Gtk::STATE_ACTIVE, color)
        entry.modify_text(Gtk::STATE_NORMAL, color)

        ew = fld_size*@middle_char_width
        ew = form_width if ew > form_width
        entry.width_request = ew
        ew,eh = entry.size_request
        field[FI_Widget] = entry
        field[FI_WidW] = ew
        field[FI_WidH] = eh
        entries_width += ew
        max_entry_height = eh if max_entry_height < eh
        entry.text = field[FI_Value].to_s
      end

      field_matrix = []
      mw, mh = 0, 0
      row = []
      row_index = -1
      rw, rh = 0, 0
      orient = :up
      @fields.each_index do |index|
        field = @fields[index]
        if (index==0) or (field[FI_NewRow]==1)
          row_index += 1
          field_matrix << row if row != []
          mw, mh = [mw, rw].max, mh+rh
          row = []
          rw, rh = 0, 0
        end

        if ! [:up, :down, :left, :right].include?(field[FI_LabOr]) then field[FI_LabOr]=orient; end
        orient = field[FI_LabOr]

        field_size = calc_field_size(field)
        rw, rh = rw+field_size[0], [rh, field_size[1]+1].max
        row << field
      end
      field_matrix << row if row != []
      mw, mh = [mw, rw].max, mh+rh

      if (mw<=form_width) and (mh<=form_height) then
        window_width, window_height = mw+36, mh+@btn_panel_height+115
      end
      window.set_default_size(window_width, window_height)

      @window_width, @window_height = 0, 0
      @old_field_matrix = []
    end

    def calc_field_size(field)
      lw = field[FI_LabW]
      lh = field[FI_LabH]
      ew = field[FI_WidW]
      eh = field[FI_WidH]
      if (field[FI_LabOr]==:left) or (field[FI_LabOr]==:right)
        [lw+ew, [lh,eh].max]
      else
        field_size = [[lw,ew].max, lh+eh]
      end
    end

    def calc_row_size(row)
      rw, rh = [0, 0]
      row.each do |fld|
        fs = calc_field_size(fld)
        rw, rh = rw+fs[0], [rh, fs[1]].max
      end
      [rw, rh]
    end

    def on_resize_window(window, event)
      if (@window_width == event.width) and (@window_height == event.height)
        return
      end
      @window_width, @window_height = event.width, event.height

      form_width = @window_width-36
      form_height = @window_height-@btn_panel_height-55

=begin
      TODO:
      H - высота элемента
      1) измерить длину всех label (W1)
      2) измерить длину всех entry (W2)
      3) сложить (W1+W2)*H - вписывается ли в квадрат, нет?
      4) измерить хитрую длину Wx = Sum [max(w1&w2)]
      5) сложить Wx*2H - вписывается ли в квадрат, нет?

      [соблюдать рекомендации по рядам, менять ориентацию, перескоки по соседству]
      1. ряды уложить по рекомендации/рекомендациям
          - если какой-нибудь ряд не лезет в ширину, начать up-ить его с конца
          - если тем не менее ряд не лезет в ширину, перемещать правые поля в начало 2х нижних
            рядов (куда лезет), или в конец верхнего соседнего, или в конец нижнего соседнего
          - если не лезет в таблицу, снизу вверх по возможности left-ить ряды,
            пока таблица не сойдется
          - если не лезла таблица, в конец верхних рядов перемещать нижние левые поля
          - если в итоге не лезет в таблицу - этап 2
          - если каждый ряд влез, и таблица влезла - на выход
      [крушить ряды с заду, потом спереди]
      2. перед оставлять рекомендованным, с заду менять:
          - заполнять с up, бить до умещения по ширине, как таблица влезла - на выход
          - заполнять с left, бить до умещения по ширине, как таблица влезла - на выход
          - выбирать up или left чтобы было минимум пустых зон
      3. спереду выбирать up или left чтобы было минимум пустых зон
      [дальние перескоки, перестановки]
      4. перемещать нижние поля (d<1) через ряды в конец верхних рядов (куда лезет), и пробовать c этапа 1
      [оставить попытки уместить в форму, использовать скроллинг]
      5a. снять ограничение по высоте таблицы, повторить с 1го этапа
      5b. следовать рекомендациям и включить скроллинг
      5c. убористо укладывать ряды (up или left) в ширину, высота таблицы без ограничений, скроллинг
      ?5d. высчитать требуемую площадь для up, уместить в гармонию, включить скроллинг
      ?5e. высчитать требуемую площадь для left, уместить в гармонию, включить скроллинг

      При каждом следующем этапе повторять все предыдущие.

      В случае, когда рекомендаций нет (все order=1.0-1.999), тогда за рекомендации разбивки считать
      относительный скачок длинны между словами идентификаторов. При этом бить число рядов исходя
      из ширины/пропорции формы.
=end

      #p '---fill'

      # create and fill field matrix to merge in form
      step = 1
      found = false
      while not found do
        fields = []
        @fields.each do |field|
          fields << field.dup
        end

        field_matrix = []
        mw, mh = 0, 0
        case step
          when 1  #normal compose. change "left" to "up" when doesn't fit to width
            row = []
            row_index = -1
            rw, rh = 0, 0
            orient = :up
            fields.each_with_index do |field, index|
              if (index==0) or (field[FI_NewRow]==1)
                row_index += 1
                field_matrix << row if row != []
                mw, mh = [mw, rw].max, mh+rh
                #p [mh, form_height]
                if (mh>form_height)
                  #step = 2
                  step = 5
                  break
                end
                row = []
                rw, rh = 0, 0
              end

              if ! [:up, :down, :left, :right].include?(field[FI_LabOr]) then field[FI_LabOr]=orient; end
              orient = field[FI_LabOr]

              field_size = calc_field_size(field)
              rw, rh = rw+field_size[0], [rh, field_size[1]].max
              row << field

              if rw>form_width
                col = row.size
                while (col>0) and (rw>form_width)
                  col -= 1
                  fld = row[col]
                  if [:left, :right].include?(fld[FI_LabOr])
                    fld[FI_LabOr]=:up
                    rw, rh = calc_row_size(row)
                  end
                end
                if (rw>form_width)
                  #step = 3
                  step = 5
                  break
                end
              end
            end
            field_matrix << row if row != []
            mw, mh = [mw, rw].max, mh+rh
            if (mh>form_height)
              #step = 2
              step = 5
            end
            found = (step==1)
          when 2
            found = true
          when 3
            found = true
          when 5  #need to rebuild rows by width
            row = []
            row_index = -1
            rw, rh = 0, 0
            orient = :up
            fields.each_with_index do |field, index|
              if ! [:up, :down, :left, :right].include?(field[FI_LabOr])
                field[FI_LabOr] = orient
              end
              orient = field[FI_LabOr]
              field_size = calc_field_size(field)

              if (rw+field_size[0]>form_width)
                row_index += 1
                field_matrix << row if row != []
                mw, mh = [mw, rw].max, mh+rh
                #p [mh, form_height]
                row = []
                rw, rh = 0, 0
              end

              row << field
              rw, rh = rw+field_size[0], [rh, field_size[1]].max

            end
            field_matrix << row if row != []
            mw, mh = [mw, rw].max, mh+rh
            found = true
          else
            found = true
        end
      end

      matrix_is_changed = @old_field_matrix.size != field_matrix.size
      if not matrix_is_changed
        field_matrix.each_index do |rindex|
          row = field_matrix[rindex]
          orow = @old_field_matrix[rindex]
          if row.size != orow.size
            matrix_is_changed = true
            break
          end
          row.each_index do |findex|
            field = row[findex]
            ofield = orow[findex]
            if (field[FI_LabOr] != ofield[FI_LabOr]) or (field[FI_LabW] != ofield[FI_LabW]) \
              or (field[FI_LabH] != ofield[FI_LabH]) \
              or (field[FI_WidW] != ofield[FI_WidW]) or (field[FI_WidH] != ofield[FI_WidH]) \
            then
              matrix_is_changed = true
              break
            end
          end
          if matrix_is_changed then break; end
        end
      end

      # compare matrix with previous
      if matrix_is_changed
        #p "----+++++redraw"
        @old_field_matrix = field_matrix

        @def_widget = focus if focus

        # delete sub-containers
        if @vbox.children.size>0
          @vbox.hide_all
          @vbox.child_visible = false
          @fields.each_index do |index|
            field = @fields[index]
            label = field[FI_Label]
            entry = field[FI_Widget]
            label.parent.remove(label)
            entry.parent.remove(entry)
          end
          @vbox.each do |child|
            child.destroy
          end
        end

        # show field matrix on form
        field_matrix.each do |row|
          row_hbox = Gtk::HBox.new
          row.each_index do |field_index|
            field = row[field_index]
            label = field[FI_Label]
            entry = field[FI_Widget]
            if (field[FI_LabOr]==nil) or (field[FI_LabOr]==:left)
              row_hbox.pack_start(label, false, false, 2)
              row_hbox.pack_start(entry, false, false, 2)
            elsif (field[FI_LabOr]==:right)
              row_hbox.pack_start(entry, false, false, 2)
              row_hbox.pack_start(label, false, false, 2)
            else
              field_vbox = Gtk::VBox.new
              if (field[FI_LabOr]==:down)
                field_vbox.pack_start(entry, false, false, 2)
                field_vbox.pack_start(label, false, false, 2)
              else
                field_vbox.pack_start(label, false, false, 2)
                field_vbox.pack_start(entry, false, false, 2)
              end
              row_hbox.pack_start(field_vbox, false, false, 2)
            end
          end
          @vbox.pack_start(row_hbox, false, false, 2)
        end
        @vbox.child_visible = true
        @vbox.show_all
        if @def_widget
          #focus = @def_widget
          @def_widget.grab_focus
        end
      end
    end

  end

  KH_None   = 0
  KH_Md5    = 0x1
  KH_Sha1   = 0x2
  KH_Sha2   = 0x3
  KH_Sha3   = 0x4

  KT_None = 0
  KT_Rsa  = 0x1
  KT_Dsa  = 0x2
  KT_Aes  = 0x6
  KT_Des  = 0x7
  KT_Bf   = 0x8
  KT_Priv = 0xF

  KL_None    = 0
  KL_bit128  = 0x10   # 16 byte
  KL_bit160  = 0x20   # 20 byte
  KL_bit224  = 0x30   # 28 byte
  KL_bit256  = 0x40   # 32 byte
  KL_bit384  = 0x50   # 48 byte
  KL_bit512  = 0x60   # 64 byte
  KL_bit1024 = 0x70   # 128 byte
  KL_bit2048 = 0x80   # 256 byte
  KL_bit4096 = 0x90   # 512 byte

  KL_BitLens = [128, 160, 224, 256, 384, 512, 1024, 2048, 4096]

  def self.klen_to_bitlen(len)
    res = nil
    ind = len >> 4
    res = KL_BitLens[ind-1] if ind and (ind>0) and (ind<=KL_BitLens.size)
    res
  end

  def self.bitlen_to_klen(len)
    res = KL_None
    ind = KL_BitLens.index(len)
    res = KL_BitLens[ind] << 4 if ind
    res
  end

  def self.divide_type_and_klen(tnl)
    type = tnl & 0x0F
    klen  = tnl & 0xF0
    [type, klen]
  end

  def self.encode_cipher_and_hash(cipher, hash)
    res = cipher & 0xFF | ((hash & 0xFF) << 8)
  end

  def self.decode_cipher_and_hash(cnh)
    cipher = cnh & 0xFF
    hash  = (cnh >> 8) & 0xFF
    [cipher, hash]
  end

  def self.pan_kh_to_openssl_hash(hash_len)
    res = nil
    #p 'hash_len='+hash_len.inspect
    hash, klen = divide_type_and_klen(hash_len)
    #p '[hash, klen]='+[hash, klen].inspect
    case hash
      when KH_Md5
        res = OpenSSL::Digest::MD5.new
      when KH_Sha1
        res = OpenSSL::Digest::SHA1.new
      when KH_Sha2
        case klen
          when KL_bit256
            res = OpenSSL::Digest::SHA256.new
          when KL_bit224
            res = OpenSSL::Digest::SHA224.new
          when KL_bit384
            res = OpenSSL::Digest::SHA384.new
          when KL_bit512
            res = OpenSSL::Digest::SHA512.new
          else
            res = OpenSSL::Digest::SHA256.new
        end
      when KH_Sha3
        case klen
          when KL_bit256
            res = SHA3::Digest::SHA256.new
          when KL_bit224
            res = SHA3::Digest::SHA224.new
          when KL_bit384
            res = SHA3::Digest::SHA384.new
          when KL_bit512
            res = SHA3::Digest::SHA512.new
          else
            res = SHA3::Digest::SHA256.new
        end
    end
    res
  end

  def self.pankt_to_openssl(type)
    res = nil
    case type
      when KT_Rsa
        res = 'RSA'
      when KT_Dsa
        res = 'DSA'
      when KT_Aes
        res = 'AES'
      when KT_Des
        res = 'DES'
      when KT_Bf
        res = 'BF'
    end
    res
  end

  def self.pankt_len_to_full_openssl(type, len)
    res = pankt_to_openssl(type)
    res += '-'+len.to_s if len
    res += '-CBC'
  end

  RSA_exponent = 65537

  KV_Obj   = 0
  KV_Key1  = 1
  KV_Key2  = 2
  KV_Kind  = 3
  KV_Ciph  = 4
  KV_Pass  = 5
  KV_Panhash = 6
  KV_Creator = 7
  KV_Trust   = 8

  def self.sym_recrypt(data, encode=true, cipher_hash=nil, cipher_key=nil)
    #p 'sym_recrypt: [cipher_hash, cipher_key]='+[cipher_hash, cipher_key].inspect
    cipher_hash ||= encode_cipher_and_hash(KT_Aes | KL_bit256, KH_Sha2 | KL_bit256)
    if cipher_hash and (cipher_hash != 0) and cipher_key and data
      ckind, chash = decode_cipher_and_hash(cipher_hash)
      hash = pan_kh_to_openssl_hash(chash)
      #p 'hash='+hash.inspect
      cipher_key = hash.digest(cipher_key) if hash
      #p 'cipher_key.hash='+cipher_key.inspect
      cipher_vec = []
      cipher_vec[KV_Key1] = cipher_key
      cipher_vec[KV_Kind] = ckind
      cipher_vec = init_key(cipher_vec)
      #p '*******'+encode.inspect
      #p '---sym_recode data='+data.inspect
      data = recrypt(cipher_vec, data, encode)
      #p '+++sym_recode data='+data.inspect
    end
    data = AsciiString.new(data) if data
    data
  end

  # Generate a key or key pair
  # RU: Генерирует ключ или ключевую пару
  def self.generate_key(type_klen = KT_Rsa | KL_bit2048, cipher_hash=nil, cipher_key=nil)
    key = nil
    key1 = nil
    key2 = nil

    type, klen = divide_type_and_klen(type_klen)
    bitlen = klen_to_bitlen(klen)

    case type
      when KT_Rsa
        bitlen ||= 2048
        bitlen = 2048 if bitlen <= 0
        key = OpenSSL::PKey::RSA.generate(bitlen, RSA_exponent)

        #key1 = ''
        #key1.force_encoding('ASCII-8BIT')
        #key2 = ''
        #key2.force_encoding('ASCII-8BIT')
        key1 = AsciiString.new(PandoraKernel.bigint_to_bytes(key.params['n']))
        key2 = AsciiString.new(PandoraKernel.bigint_to_bytes(key.params['p']))
        #p key1 = key.params['n']
        #key2 = key.params['p']
        #p PandoraKernel.bytes_to_bigin(key1)
        #p '************8'

        #puts key.to_text
        #p key.params

        #key_der = key.to_der
        #p key_der.size

        #key = OpenSSL::PKey::RSA.new(key_der)
        #p 'pub_seq='+asn_seq2 = OpenSSL::ASN1.decode(key.public_key.to_der).inspect
      else #симметричный ключ
        #p OpenSSL::Cipher::ciphers
        key = OpenSSL::Cipher.new(pankt_len_to_full_openssl(type, bitlen))
        key.encrypt
        key1 = cipher.random_key
        key2 = cipher.random_iv
        #p key1.size
        #p key2.size
    end
    if cipher_key and cipher_key==''
      cipher_hash = 0
      cipher_key = nil
    else
      key2 = sym_recrypt(key2, true, cipher_hash, cipher_key)
    end
    [key, key1, key2, type_klen, cipher_hash, cipher_key]
  end

  # Init key or key pare
  # RU: Инициализирует ключ или ключевую пару
  def self.init_key(key_vec)
    key = key_vec[KV_Obj]
    if not key
      key1 = key_vec[KV_Key1]
      key2 = key_vec[KV_Key2]
      type_klen = key_vec[KV_Kind]
      cipher = key_vec[KV_Ciph]
      pass = key_vec[KV_Pass]
      type, klen = divide_type_and_klen(type_klen)
      bitlen = klen_to_bitlen(klen)
      case type
        when KT_Rsa
          #p '------'
          #p key.params
          n = PandoraKernel.bytes_to_bigint(key1)
          #p 'n='+n.inspect
          e = OpenSSL::BN.new(RSA_exponent.to_s)
          p0 = nil
          if key2
            key2 = sym_recrypt(key2, false, cipher, pass)
            p0 = PandoraKernel.bytes_to_bigint(key2) if key2
          else
            p0 = 0
          end

          if p0
            pass = 0

            #p 'n='+n.inspect+'  p='+p0.inspect+'  e='+e.inspect

            if key2
              q = (n / p0)[0]
              p0,q = q,p0 if p0 < q
              d = e.mod_inverse((p0-1)*(q-1))
              dmp1 = d % (p0-1)
              dmq1 = d % (q-1)
              iqmp = q.mod_inverse(p0)

              #p '[n,d,dmp1,dmq1,iqmp]='+[n,d,dmp1,dmq1,iqmp].inspect

              seq = OpenSSL::ASN1::Sequence([
                OpenSSL::ASN1::Integer(pass),
                OpenSSL::ASN1::Integer(n),
                OpenSSL::ASN1::Integer(e),
                OpenSSL::ASN1::Integer(d),
                OpenSSL::ASN1::Integer(p0),
                OpenSSL::ASN1::Integer(q),
                OpenSSL::ASN1::Integer(dmp1),
                OpenSSL::ASN1::Integer(dmq1),
                OpenSSL::ASN1::Integer(iqmp)
              ])
            else
              seq = OpenSSL::ASN1::Sequence([
                OpenSSL::ASN1::Integer(n),
                OpenSSL::ASN1::Integer(e),
              ])
            end

            #p asn_seq = OpenSSL::ASN1.decode(key)
            # Seq: Int:pass, Int:n, Int:e, Int:d, Int:p, Int:q, Int:dmp1, Int:dmq1, Int:iqmp
            #seq1 = asn_seq.value[1]
            #str_val = PandoraKernel.bigint_to_bytes(seq1.value)
            #p 'str_val.size='+str_val.size.to_s
            #p Base64.encode64(str_val)
            #key2 = key.public_key
            #p key2.to_der.size
            # Seq: Int:n, Int:e
            #p 'pub_seq='+asn_seq2 = OpenSSL::ASN1.decode(key.public_key.to_der).inspect
            #p key2.to_s

            # Seq: Int:pass, Int:n, Int:e, Int:d, Int:p, Int:q, Int:dmp1, Int:dmq1, Int:iqmp
            key = OpenSSL::PKey::RSA.new(seq.to_der)
            #p key.params
          end
        when KT_Dsa
          seq = OpenSSL::ASN1::Sequence([
            OpenSSL::ASN1::Integer(0),
            OpenSSL::ASN1::Integer(key.p),
            OpenSSL::ASN1::Integer(key.q),
            OpenSSL::ASN1::Integer(key.g),
            OpenSSL::ASN1::Integer(key.pub_key),
            OpenSSL::ASN1::Integer(key.priv_key)
          ])
        else
          key = OpenSSL::Cipher.new(pankt_len_to_full_openssl(type, bitlen))
          key.key = key1
      end
      key_vec[KV_Obj] = key
    end
    key_vec
  end

  # Create sign
  # RU: Создает подпись
  def self.make_sign(key, data, hash_len=KH_Sha2 | KL_bit256)
    sign = nil
    sign = key[KV_Obj].sign(pan_kh_to_openssl_hash(hash_len), data) if key[KV_Obj]
    sign
  end

  # Verify sign
  # RU: Проверяет подпись
  def self.verify_sign(key, data, sign, hash_len=KH_Sha2 | KL_bit256)
    res = false
    res = key[KV_Obj].verify(pan_kh_to_openssl_hash(hash_len), sign, data) if key[KV_Obj]
    res
  end

  #def self.encode_pan_cryptomix(type, cipher, hash)
  #  mix = type & 0xFF | (cipher << 8) & 0xFF | (hash << 16) & 0xFF
  #end

  #def self.decode_pan_cryptomix(mix)
  #  type = mix & 0xFF
  #  cipher = (mix >> 8) & 0xFF
  #  hash = (mix >> 16) & 0xFF
  #  [type, cipher, hash]
  #end

  #def self.detect_key(key)
  #  [key, type, klen, cipher, hash, hlen]
  #end

  # Encrypt data
  # RU: Шифрует данные
  def self.recrypt(key_vec, data, encrypt=true, private=false)
    recrypted = nil
    key = key_vec[KV_Obj]
    #p 'encrypt key='+key.inspect
    if key.is_a? OpenSSL::Cipher
      iv = nil
      if encrypt
        key.encrypt
        key.key = key_vec[KV_Key1]
        iv = key.random_iv
      else
        data = AsciiString.new(data)
        #data.force_encoding('ASCII-8BIT')
        data, len = pson_elem_to_rubyobj(data)   # pson to array
        #p 'decrypt: data='+data.inspect
        key.decrypt
        #p 'DDDDDDEEEEECR'
        iv = AsciiString.new(data[1])
        data = AsciiString.new(data[0])  # data from array
        key.key = key_vec[KV_Key1]
        key.iv = iv
      end

      begin
        #p 'BEFORE key='+key.key.inspect
        recrypted = key.update(data) + key.final
      rescue
        recrypted = nil
      end

      #p '[recrypted, iv]='+[recrypted, iv].inspect
      if encrypt and recrypted
        recrypted = rubyobj_to_pson_elem([recrypted, iv])
      end

    else  #elsif key.is_a? OpenSSL::PKey
      if encrypt
        if private
          recrypted = key.public_encrypt(data)
        else
          p 'recrypt  data.inspect='+data.inspect+'  key='+key.inspect
          recrypted = key.public_encrypt(data)
        end
      else
        if private
          recrypted = key.public_decrypt(data)
        else
          recrypted = key.public_decrypt(data)
        end
      end
    end
    recrypted
  end

  def self.create_base_id
    res = PandoraKernel.fill_zeros_from_left(PandoraKernel.bigint_to_bytes(Time.now.to_i), 4)[0,4]
    res << OpenSSL::Random.random_bytes(12)
    res
  end

  PT_Int   = 0
  PT_Str   = 1
  PT_Bool  = 2
  PT_Time  = 3
  PT_Array = 4
  PT_Hash  = 5
  PT_Sym   = 6
  PT_Unknown = 32

  def self.string_to_pantype(type)
    res = PT_Unknown
    case type
      when 'Integer', 'Word', 'Byte', 'Coord'
        res = PT_Int
      when 'String', 'Text', 'Blob'
        res = PT_Str
      when 'Boolean'
        res = PT_Bool
      when 'Time', 'Date'
        res = PT_Time
      when 'Array'
        res = PT_Array
      when 'Hash'
        res = PT_Hash
      when 'Symbol'
        res = PT_Sym
    end
    res
  end

  def self.pantype_to_view(type)
    res = nil
    case type
      when PT_Int
        res = 'integer'
      when PT_Bool
        res = 'boolean'
      when PT_Time
        res = 'time'
    end
    res
  end

  def self.decode_param_setting(setting)
    res = {}
    i = setting.index('"')
    j = nil
    j = setting.index('"', i+1) if i
    if i and j
      res['default'] = setting[i+1..j-1]
      i = setting.index(',', j+1)
      i ||= j
      res['view'] = setting[i+1..-1]
    else
      sets = setting.split(',')
      res['default'] = sets[0]
      res['view'] = sets[1]
    end
    res
  end

  def self.create_default_param(type, setting)
    value = nil
    if setting
      ps = decode_param_setting(setting)
      defval = ps['default']
      if defval and defval[0]=='['
        i = defval.index(']')
        i ||= defval.size
        value = self.send(defval[1,i-1])
      else
        type = string_to_pantype(type) if type.is_a? String
        case type
          when PT_Int
            if defval
              value = defval.to_i
            else
              value = 0
            end
          when PT_Bool
            value = (defval and ((defval.downcase=='true') or (defval=='1')))
          when PT_Time
            if defval
              value = Time.parse(defval)  #Time.strptime(defval, '%d.%m.%Y')
            else
              value = 0
            end
          else
            value = defval
            value ||= ''
        end
      end
    end
    value
  end

  $model_gui = {}

  def self.model_gui(ider, models=nil)
    if models
      res = models[ider]
    else
      res = $model_gui[ider]
    end
    if not res
      if PandoraModel.const_defined? ider
        panobj_class = PandoraModel.const_get(ider)
        res = panobj_class.new
        if models
          models[ider] = res
        else
          $model_gui[ider] = res
        end
      end
    end
    res
  end

  def self.get_param(name, get_id=false)
    value = nil
    id = nil
    param_model = model_gui('Parameter')
    sel = param_model.select({'name'=>name}, false, 'value, id')
    if not sel[0]
      # parameter was not found
      ind = $pandora_parameters.index{ |row| row[PF_Name]==name }
      if ind
        # default description is found, create parameter
        row = $pandora_parameters[ind]
        type = row[PF_Type]
        type = string_to_pantype(type) if type.is_a? String
        section = row[PF_Section]
        section = get_param('section_'+section) if section.is_a? String
        section ||= row[PF_Section].to_i
        values = { :name=>name, :desc=>row[PF_Desc],
          :value=>create_default_param(type, row[PF_Setting]), :type=>type,
          :section=>section, :setting=>row[PF_Setting], :modified=>Time.now.to_i }
        panhash = param_model.panhash(values)
        values['panhash'] = panhash
        param_model.update(values, nil, nil)
        sel = param_model.select({'name'=>name}, false, 'value, id')
      end
    end
    if sel[0]
      # value exists
      value = sel[0][0]
      id = sel[0][1] if get_id
    end
    value = [value, id] if get_id
    #p 'get_param value='+value.inspect
    value
  end

  def self.set_param(name, value, definition=nil)
    res = false
    old_value, id = get_param(name, true)
    param_model = model_gui('Parameter')
    if (value != old_value) and param_model
      values = {:value=>value, :modified=>Time.now.to_i}
      res = param_model.update(values, nil, 'id='+id.to_s)
    end
    res
  end

  class << self
    attr_accessor :the_current_key
  end

  SF_Update = 0
  SF_Auth   = 1
  SF_Listen = 2
  SF_Hunt   = 3
  SF_Conn   = 4

  $status_fields = []

  def self.add_status_field(index, text)
    $statusbar.pack_start(Gtk::SeparatorToolItem.new, false, false, 0) if ($status_fields != [])
    btn = Gtk::Button.new(_(text))
    btn.relief = Gtk::RELIEF_NONE
    if block_given?
      btn.signal_connect('clicked') do |*args|
        yield(*args)
      end
    end
    $statusbar.pack_start(btn, false, false, 0)
    $status_fields[index] = btn
  end

  $toggle_buttons = []

  def self.set_status_field(index, text, enabled=nil, toggle=nil)
    btn = $status_fields[index]
    if btn
      btn.label = _(text) if $status_fields[index]
      if (enabled != nil)
        btn.sensitive = enabled
      end
      if (toggle != nil) and $toggle_buttons[index]
        $toggle_buttons[index].good_set_active(toggle)
      end
    end
  end

  def self.get_status_field(index)
    $status_fields[index]
  end

  $update_interval = 30
  $download_thread = nil

  # Check updated files and download them
  # RU: Проверить обновления и скачать их
  def self.start_updating(all_step=true)

    upd_list = ['model/01-base.xml', 'model/02-forms.xml', 'pandora.sh', 'model/03-language-ru.xml', \
      'lang/ru.txt', 'pandora.bat']

    def self.update_file(http, path, pfn)
      res = false
      begin
        #p [path, pfn]
        response = http.request_get(path)
        File.open(pfn, 'wb+') do |file|
          file.write(response.body)
          res = true
          log_message(LM_Info, _('File is updated')+': '+pfn)
        end
      rescue => err
        puts 'Update error: '+err.message
      end
      res
    end

    if $download_thread and $download_thread.alive?
      $download_thread[:all_step] = all_step
      $download_thread.run if $download_thread.stop?
    else
      $download_thread = Thread.new do
        Thread.current[:all_step] = all_step
        downloaded = false

        set_status_field(SF_Update, 'Need check')
        sleep($update_interval) if not Thread.current[:all_step]

        set_status_field(SF_Update, 'Checking')
        main_script = File.join($pandora_root_dir, 'pandora.rb')
        curr_size = File.size?(main_script)
        if curr_size
          arch_name = File.join($pandora_root_dir, 'master.zip')
          main_uri = URI('https://raw.github.com/Novator/Pandora/master/pandora.rb')
          #arch_uri = URI('https://codeload.github.com/Novator/Pandora/zip/master')

          time = 0
          http = nil
          if File.stat(main_script).writable?
            begin
              #p '-----------'
              #p [main_uri.host, main_uri.port, main_uri.path]
              http = Net::HTTP.new(main_uri.host, main_uri.port)
              http.use_ssl = true
              http.verify_mode = OpenSSL::SSL::VERIFY_NONE
              http.open_timeout = 60*5
              response = http.request_head(main_uri.path)
              PandoraGUI.set_param('last_check', Time.now)
              if (response.content_length == curr_size)
                http = nil
                set_status_field(SF_Update, 'Updated', true)
                PandoraGUI.set_param('last_update', Time.now)
              else
                time = Time.now.to_i
              end
            rescue => err
              http = nil
              set_status_field(SF_Update, 'Connection error')
              log_message(LM_Warning, _('Connection error')+' 1')
              puts err.message
            end
          else
            set_status_field(SF_Update, 'Read only')
          end
          if http
            set_status_field(SF_Update, 'Need update')
            Thread.stop

            if Time.now.to_i >= time + 60*5
              begin
                http = Net::HTTP.new(main_uri.host, main_uri.port)
                http.use_ssl = true
                http.verify_mode = OpenSSL::SSL::VERIFY_NONE
                http.open_timeout = 60*5
              rescue => err
                http = nil
                set_status_field(SF_Update, 'Connection error')
                log_message(LM_Warning, _('Connection error')+' 2')
                puts err.message
              end
            end

            if http
              set_status_field(SF_Update, 'Updating')
              downloaded = update_file(http, main_uri.path, main_script)
              upd_list.each do |fn|
                pfn = File.join($pandora_root_dir, fn)
                if File.exist?(pfn) and File.stat(pfn).writable?
                  downloaded = downloaded and update_file(http, '/Novator/Pandora/master/'+fn, pfn)
                else
                  downloaded = false
                  log_message(LM_Warning, _('Not exist or read only')+': '+pfn)
                end
              end
              if downloaded
                PandoraGUI.set_param('last_update', Time.now)
                set_status_field(SF_Update, 'Need reboot')
                Thread.stop
                Gtk.main_quit
              else
                set_status_field(SF_Update, 'Updating error')
              end
            end
          end
        end
        $download_thread = nil
      end
    end
  end

  def self.fill_by_zeros(str)
    if str.is_a? String
      (str.size).times do |i|
        str[i] = 0.chr
      end
    end
  end

  # Deactivate current or target key
  # RU: Деактивирует текущий или указанный ключ
  def self.deactivate_key(key_vec)
    if key_vec.is_a? Array
      fill_by_zeros(key_vec[KV_Key2])  #private key
      fill_by_zeros(key_vec[KV_Pass])
      key_vec.each_index do |i|
        key_vec[i] = nil
      end
    end
    key_vec = nil
  end

  def self.reset_current_key
    self.the_current_key = deactivate_key(self.the_current_key)
    set_status_field(SF_Auth, 'Not logged', nil, false)
    self.the_current_key
  end

  KR_Exchange  = 1
  KR_Sign      = 2

  $key_model = nil

  def self.current_key(switch_key=false, need_init=true)
    key_vec = self.the_current_key
    if key_vec and switch_key
      key_vec = reset_current_key
    elsif (not key_vec) and need_init
      try = true
      while try
        try = false
        creator = nil
        key_model = model_gui('Key')
        last_auth_key = get_param('last_auth_key')
        if last_auth_key.is_a? Integer
          last_auth_key = AsciiString.new(PandoraKernel.bigint_to_bytes(last_auth_key))
        end
        if last_auth_key and (last_auth_key != '')
          filter = {:panhash => last_auth_key}
          sel = key_model.select(filter, false)
          #p 'curkey  sel='+sel.inspect
          if sel and (sel.size>1)

            kind0 = key_model.field_val('kind', sel[0])
            kind1 = key_model.field_val('kind', sel[1])
            body0 = key_model.field_val('body', sel[0])
            body1 = key_model.field_val('body', sel[1])

            type0, klen0 = divide_type_and_klen(kind0)
            cipher = 0
            if type0==KT_Priv
              priv = body0
              pub = body1
              kind = kind1
              cipher = key_model.field_val('cipher', sel[0])
              creator = key_model.field_val('creator', sel[0])
            else
              priv = body1
              pub = body0
              kind = kind0
              cipher = key_model.field_val('cipher', sel[1])
              creator = key_model.field_val('creator', sel[1])
            end
            cipher ||= 0

            passwd = nil
            if cipher != 0
              dialog = AdvancedDialog.new(_('Key init'))
              dialog.set_default_size(400, 190)

              vbox = Gtk::VBox.new
              dialog.viewport.add(vbox)

              label = Gtk::Label.new(_('Key'))
              vbox.pack_start(label, false, false, 2)
              entry = Gtk::Entry.new
              entry.text = PandoraKernel.bytes_to_hex(last_auth_key)
              entry.editable = false
              vbox.pack_start(entry, false, false, 2)

              label = Gtk::Label.new(_('Password'))
              vbox.pack_start(label, false, false, 2)
              entry = Gtk::Entry.new
              entry.visibility = false
              vbox.pack_start(entry, false, false, 2)
              dialog.def_widget = entry

              try = true
              dialog.run do
                passwd = entry.text
                try = false
              end
            end

            if not try
              key_vec = []
              key_vec[KV_Key1] = pub
              key_vec[KV_Key2] = priv
              key_vec[KV_Kind] = kind
              key_vec[KV_Pass] = passwd
              key_vec[KV_Panhash] = last_auth_key
              key_vec[KV_Creator] = creator
            end
          end
        end
        if (not key_vec) and (not try)
          dialog = AdvancedDialog.new(_('Key generation'))
          dialog.set_default_size(400, 250)

          vbox = Gtk::VBox.new
          dialog.viewport.add(vbox)

          #creator = PandoraKernel.bigint_to_bytes(0x01052ec783d34331de1d39006fc80000000000000000)
          label = Gtk::Label.new(_('Your panhash'))
          vbox.pack_start(label, false, false, 2)
          user_entry = Gtk::Entry.new
          #user_entry.text = PandoraKernel.bytes_to_hex(creator)
          vbox.pack_start(user_entry, false, false, 2)

          rights = KR_Exchange | KR_Sign
          label = Gtk::Label.new(_('Rights'))
          vbox.pack_start(label, false, false, 2)
          rights_entry = Gtk::Entry.new
          rights_entry.text = rights.to_s
          vbox.pack_start(rights_entry, false, false, 2)

          label = Gtk::Label.new(_('Password'))
          vbox.pack_start(label, false, false, 2)
          pass_entry = Gtk::Entry.new
          vbox.pack_start(pass_entry, false, false, 2)

          dialog.def_widget = pass_entry

          dialog.run do
            creator = PandoraKernel.hex_to_bytes(user_entry.text)
            if creator.size==22
              #cipher_hash = encode_cipher_and_hash(KT_Bf, KH_Sha2 | KL_bit256)
              cipher_hash = encode_cipher_and_hash(KT_Aes | KL_bit256, KH_Sha2 | KL_bit256)
               cipher_key = pass_entry.text
              rights = rights_entry.text.to_i

              #p 'cipher_hash='+cipher_hash.to_s
              type_klen = KT_Rsa | KL_bit2048

              key_vec = generate_key(type_klen, cipher_hash, cipher_key)

              #p 'key_vec='+key_vec.inspect

              pub  = key_vec[KV_Key1]
              priv = key_vec[KV_Key2]
              type_klen = key_vec[KV_Kind]
              cipher_hash = key_vec[KV_Ciph]
              cipher_key = key_vec[KV_Pass]

              key_vec[KV_Creator] = creator

              time_now = Time.now

              vals = time_now.to_a
              y, m, d = [vals[5], vals[4], vals[3]]  #current day
              expire = Time.local(y+5, m, d).to_i

              time_now = time_now.to_i

              panstate = PSF_Support

              values = {:panstate=>panstate, :kind=>type_klen, :rights=>rights, :expire=>expire, \
                :creator=>creator, :created=>time_now, :cipher=>0, :body=>pub, :modified=>time_now}
              panhash = key_model.panhash(values, rights)
              values['panhash'] = panhash
              key_vec[KV_Panhash] = panhash

              res = key_model.update(values, nil, nil)
              if res
                values[:kind] = KT_Priv
                values[:body] = priv
                values[:cipher] = cipher_hash
                res = key_model.update(values, nil, nil)
                if res
                  #p 'last_auth_key='+panhash.inspect
                  set_param('last_auth_key', panhash)
                end
              end
            else
              dialog = Gtk::MessageDialog.new($window, \
                Gtk::Dialog::MODAL | Gtk::Dialog::DESTROY_WITH_PARENT, \
                Gtk::MessageDialog::INFO, Gtk::MessageDialog::BUTTONS_OK_CANCEL, \
                _('Panhash must consist of 44 symbols'))
              dialog.title = _('Note')
              dialog.default_response = Gtk::Dialog::RESPONSE_OK
              dialog.icon = $window.icon
              if (dialog.run == Gtk::Dialog::RESPONSE_OK)
                PandoraGUI.do_menu_act('Person')
              end
              dialog.destroy
            end
          end
        end
        try = false
        if key_vec
          key_vec = init_key(key_vec)
          #p 'key_vec='+key_vec.inspect
          if key_vec and key_vec[KV_Obj]
            self.the_current_key = key_vec
            set_status_field(SF_Auth, 'Logged', nil, true)
          elsif last_auth_key
            dialog = Gtk::MessageDialog.new($window, Gtk::Dialog::MODAL | Gtk::Dialog::DESTROY_WITH_PARENT, \
              Gtk::MessageDialog::QUESTION, Gtk::MessageDialog::BUTTONS_OK_CANCEL, \
              _('Bad password. Try again?')+"\n[" +PandoraKernel.bytes_to_hex(last_auth_key[2,16])+']')
            dialog.title = _('Key init')
            dialog.default_response = Gtk::Dialog::RESPONSE_OK
            dialog.icon = $window.icon
            try = (dialog.run == Gtk::Dialog::RESPONSE_OK)
            dialog.destroy
            key_vec = deactivate_key(key_vec) if (not try)
          end
        else
          key_vec = deactivate_key(key_vec)
        end
      end
    end
    key_vec
  end

  def self.current_user_or_key(user=true, init=true)
    panhash = nil
    key = current_key(false, init)
    if key and key[KV_Obj]
      if user
        panhash = key[KV_Creator]
      else
        panhash = key[KV_Panhash]
      end
    end
    panhash
  end

  # Encode data type and size to PSON type and count of size in bytes (1..8)-1
  # RU: Кодирует тип данных и размер в тип PSON и число байт размера
  def self.encode_pson_type(basetype, int)
    count = 0
    while (int>0xFF) and (count<8)
      int = int >> 8
      count +=1
    end
    if count >= 8
      puts '[encode_pan_type] Too big int='+int.to_s
      count = 7
    end
    [basetype ^ (count << 5), count]
  end

  # Decode PSON type to data type and count of size in bytes (1..8)-1
  # RU: Раскодирует тип PSON в тип данных и число байт размера
  def self.decode_pson_type(type)
    basetype = type & 0x1F
    count = type >> 5
    [basetype, count]
  end

  # Convert ruby object to PSON (Pandora Simple Object Notation)
  # RU: Конвертирует объект руби в PSON ("простая нотация объектов в Пандоре")
  def self.rubyobj_to_pson_elem(rubyobj)
    type = PT_Unknown
    count = 0
    data = AsciiString.new
    elem_size = nil
    case rubyobj
      when String
        data << rubyobj
        elem_size = data.bytesize
        type, count = encode_pson_type(PT_Str, elem_size)
      when Symbol
        data << rubyobj.to_s
        elem_size = data.bytesize
        type, count = encode_pson_type(PT_Sym, elem_size)
      when Integer
        data << PandoraKernel.bigint_to_bytes(rubyobj)
        type, count = encode_pson_type(PT_Int, rubyobj)
      when TrueClass, FalseClass
        if rubyobj
          data << [1].pack('C')
        else
          data << [0].pack('C')
        end
        type = PT_Bool
      when Time
        data << PandoraKernel.bigint_to_bytes(rubyobj.to_i)
        type, count = encode_pson_type(PT_Time, rubyobj.to_i)
      when Array
        rubyobj.each do |a|
          data << rubyobj_to_pson_elem(a)
        end
        elem_size = rubyobj.size
        type, count = encode_pson_type(PT_Array, elem_size)
      when Hash
        rubyobj = rubyobj.sort_by {|k,v| k.to_s}
        rubyobj.each do |a|
          data << rubyobj_to_pson_elem(a[0]) << rubyobj_to_pson_elem(a[1])
        end
        elem_size = rubyobj.bytesize
        type, count = encode_pson_type(PT_Hash, elem_size)
      else
        puts 'Unknown elem type: ['+rubyobj.class.name+']'
    end
    res = AsciiString.new
    res << [type].pack('C')
    if elem_size
      res << PandoraKernel.fill_zeros_from_left(PandoraKernel.bigint_to_bytes(elem_size), count+1) + data
    else
      res << PandoraKernel.fill_zeros_from_left(data, count+1)
    end
    res = AsciiString.new(res)
  end

  # Convert PSON to ruby object
  # RU: Конвертирует PSON в объект руби
  def self.pson_elem_to_rubyobj(data)
    data = AsciiString.new(data)
    val = nil
    len = 0
    if data.bytesize>0
      type = data[0].ord
      len = 1
      basetype, vlen = decode_pson_type(type)
      #p 'basetype, vlen='+[basetype, vlen].inspect
      vlen += 1
      if data.bytesize >= len+vlen
        int = PandoraKernel.bytes_to_int(data[len, vlen])
        case basetype
          when PT_Int
            val = int
          when PT_Bool
            val = (int != 0)
          when PT_Time
            val = Time.at(int)
          when PT_Str, PT_Sym
            pos = len+vlen
            if pos+int>data.bytesize
              int = data.bytesize-pos
            end
            val = ''
            val << data[pos, int]
            vlen += int
            val = data[pos, int].to_sym if basetype == PT_Sym
          when PT_Array, PT_Hash
            val = []
            int *= 2 if basetype == PT_Hash
            while (data.bytesize-1-vlen>0) and (int>0)
              int -= 1
              aval, alen = pson_elem_to_rubyobj(data[len+vlen..-1])
              val << aval
              vlen += alen
            end
            val = Hash[*val] if basetype == PT_Hash
        end
        len += vlen
        #p '[val,len]='+[val,len].inspect
      else
        len = data.bytesize
      end
    end
    [val, len]
  end

  def self.value_is_empty(val)
    res = (val==nil) or (val.is_a? String and (val=='')) or (val.is_a? Integer and (val==0)) \
      or (val.is_a? Array and (val==[])) or (val.is_a? Hash and (val=={})) \
      or (val.is_a? Time and (val.to_i==0))
    res
  end

  # Pack PanObject fields to PSON binary format
  # RU: Пакует поля ПанОбъекта в бинарный формат PSON
  def self.namehash_to_pson(fldvalues, pack_empty=false)
    #bytes = ''
    #bytes.force_encoding('ASCII-8BIT')
    bytes = AsciiString.new
    fldvalues = fldvalues.sort_by {|k,v| k.to_s } # sort by key
    fldvalues.each { |nam, val|
      if pack_empty or (not value_is_empty(val))
        nam = nam.to_s
        nsize = nam.bytesize
        nsize = 255 if nsize>255
        bytes << [nsize].pack('C') + nam[0, nsize]
        pson_elem = rubyobj_to_pson_elem(val)
        #pson_elem.force_encoding('ASCII-8BIT')
        bytes << pson_elem
      end
    }
    bytes = AsciiString.new(bytes)
  end

  def self.pson_to_namehash(pson)
    hash = {}
    while pson and (pson.bytesize>1)
      flen = pson[0].ord
      fname = pson[1, flen]
      #p '[flen, fname]='+[flen, fname].inspect
      if (flen>0) and fname and (fname.bytesize>0)
        val = nil
        if pson.bytesize-flen>1
          pson = pson[1+flen..-1]  # drop getted name
          val, len = pson_elem_to_rubyobj(pson)
          pson = pson[len..-1]     # drop getted value
        else
          pson = nil
        end
        hash[fname] = val
      else
        pson = nil
        hash = nil if hash == {}
      end
    end
    hash
  end

  def self.normalize_trust(trust, to_int=nil)
    if trust.is_a? Integer
      if trust<(-127)
        trust = -127
      elsif trust>127
        trust = 127
      end
      trust = (trust/127.0) if to_int == false
    elsif trust.is_a? Float
      if trust<(-1.0)
        trust = -1.0
      elsif trust>1.0
        trust = 1.0
      end
      trust = (trust * 127).round if to_int == true
    else
      trust = nil
    end
    trust
  end

  PT_Pson1   = 1

  $sign_model = nil

  # Sign PSON of PanObject and save sign record
  # RU: Подписывает PSON ПанОбъекта и сохраняет запись подписи
  def self.sign_panobject(panobject, trust=0, models=nil)
    res = false
    key = current_key
    if key and key[KV_Obj] and key[KV_Creator]
      namesvalues = panobject.namesvalues
      matter_fields = panobject.matter_fields
      #p 'sign: matter_fields='+matter_fields.inspect
      sign = make_sign(key, namehash_to_pson(matter_fields))

      time_now = Time.now.to_i
      obj_hash = namesvalues['panhash']
      key_hash = key[KV_Panhash]
      creator = key[KV_Creator]

      trust = normalize_trust(trust, true)

      values = {:modified=>time_now, :obj_hash=>obj_hash, :key_hash=>key_hash, :pack=>PT_Pson1, \
        :trust=>trust, :creator=>creator, :created=>time_now, :sign=>sign}

      sign_model = model_gui('Sign', models)
      panhash = sign_model.panhash(values)
      #p '!!!!!!panhash='+PandoraKernel.bytes_to_hex(panhash).inspect

      values['panhash'] = panhash

      res = sign_model.update(values, nil, nil)
    end
    res
  end

  def self.unsign_panobject(obj_hash, delete_all=false, models=nil)
    res = true
    key_hash = current_user_or_key(false, (not delete_all))
    if obj_hash and (delete_all or key_hash)
      sign_model = model_gui('Sign', models)
      filter = {:obj_hash=>obj_hash}
      filter[:key_hash] = key_hash if key_hash
      res = sign_model.update(nil, nil, filter)
    end
    res
  end

  def self.trust_of_panobject(panhash, models=nil)
    res = nil
    if panhash and (panhash != '')
      key_hash = current_user_or_key(false, false)
      sign_model = model_gui('Sign', models)
      filter = {:obj_hash => panhash}
      filter[:key_hash] = key_hash if key_hash
      sel = sign_model.select(filter, false, 'created, trust')
      if sel and (sel.size>0)
        if key_hash
          last_date = 0
          sel.each_with_index do |row, i|
            created = row[0]
            trust = row[1]
            #p 'sign: [creator, created, trust]='+[creator, created, trust].inspect
            #p '[prev_creator, created, last_date, creator]='+[prev_creator, created, last_date, creator].inspect
            if created>last_date
              #p 'sign2: [creator, created, trust]='+[creator, created, trust].inspect
              last_date = created
              res = normalize_trust(trust, false)
            end
          end
        else
          res = sel.size
        end
      end
    end
    res
  end

  $person_trusts = {}

  def self.trust_of_person(panhash, level=0)
    res = $person_trusts[panhash]
    if res
      res = 0.0
      trust_level = 0
      if not my_key_hash
        my_key_hash = current_user_or_key(false, false)
        p 'trust of person'
      end
    end
    res
  end

  $query_depth = 3

  def self.rate_of_panobj(panhash, depth=$query_depth, querist=nil, models=nil)
    count = 0
    rate = 0.0
    querist_rate = nil
    depth -= 1
    if (depth >= 0) and (panhash != querist) and panhash and (panhash != '')
      if (not querist) or (querist == '')
        querist = current_user_or_key(false, true)
      end
      if querist and (querist != '')
        #kind = PandoraKernel.kind_from_panhash(panhash)
        sign_model = model_gui('Sign', models)
        filter = { :obj_hash => panhash, :key_hash => querist }
        #filter = {:obj_hash => panhash}
        sel = sign_model.select(filter, false, 'creator, created, trust', 'creator')
        if sel and (sel.size>0)
          prev_creator = nil
          last_date = 0
          last_trust = nil
          last_i = sel.size-1
          sel.each_with_index do |row, i|
            creator = row[0]
            created = row[1]
            trust = row[2]
            #p 'sign: [creator, created, trust]='+[creator, created, trust].inspect
            if creator
              #p '[prev_creator, created, last_date, creator]='+[prev_creator, created, last_date, creator].inspect
              if (not prev_creator) or ((created>last_date) and (creator==prev_creator))
                #p 'sign2: [creator, created, trust]='+[creator, created, trust].inspect
                last_date = created
                last_trust = trust
                prev_creator ||= creator
              end
              if (creator != prev_creator) or (i==last_i)
                p 'sign3: [creator, created, last_trust]='+[creator, created, last_trust].inspect
                person_trust = 1.0 #trust_of_person(creator, my_key_hash)
                rate += normalize_trust(last_trust, false) * person_trust
                prev_creator = creator
                last_date = created
                last_trust = trust
              end
            end
          end
        end
        querist_rate = rate
      end
    end
    [count, rate, querist_rate]
  end

  # Realtion kinds
  # RU: Виды связей
  RK_Unknown  = 0
  RK_Equal    = 1
  RK_Similar  = 2
  RK_Antipod  = 3
  RK_PartOf   = 4
  RK_Cause    = 5
  RK_Follow   = 6
  RK_Ignore   = 7
  RK_CameFrom = 8
  RK_MinPublic = 235
  RK_MaxPublic = 255

  # Relation is symmetric
  # RU: Связь симметрична
  def self.relation_is_symmetric(relation)
    res = [RK_Equal, RK_Similar, RK_Unknown].include? relation
  end

  # Check, create or delete relation between two panobjects
  # RU: Проверяет, создаёт или удаляет связь между двумя объектами
  def self.act_relation(panhash1, panhash2, rel_kind=RK_Unknown, act=:check, creator=true, \
  init=false, models=nil)
    res = nil
    if panhash1 or panhash2
      if not (panhash1 and panhash2)
        panhash = current_user_or_key(creator, init)
        if panhash
          if not panhash1
            panhash1 = panhash
          else
            panhash2 = panhash
          end
        end
      end
      if panhash1 and panhash2 #and (panhash1 != panhash2)
        #p 'relat [p1,p2,t]='+[PandoraKernel.bytes_to_hex(panhash1), PandoraKernel.bytes_to_hex(panhash2), rel_kind.inspect
        relation_model = model_gui('Relation', models)
        if relation_model
          filter = {:first => panhash1, :second => panhash2, :kind => rel_kind}
          filter2 = nil
          if relation_is_symmetric(rel_kind) and (panhash1 != panhash2)
            filter2 = {:first => panhash2, :second => panhash1, :kind => rel_kind}
          end
          #p 'relat2 [p1,p2,t]='+[PandoraKernel.bytes_to_hex(panhash1), PandoraKernel.bytes_to_hex(panhash2), rel_kind].inspect
          #p 'act='+act.inspect
          if (act != :delete)  #check or create
            #p 'check or create'
            sel = relation_model.select(filter, false, 'id')
            exist = (sel and (sel.size>0))
            if not exist and filter2
              sel = relation_model.select(filter2, false, 'id')
              exist = (sel and (sel.size>0))
            end
            res = exist
            if not exist and (act == :create)
              #p 'UPD!!!'
              if filter2 and (panhash1>panhash2) #when symmetric relation less panhash must be at left
                filter = filter2
              end
              panhash = relation_model.panhash(filter, 0)
              filter['panhash'] = panhash
              filter['modified'] = Time.now.to_i
              res = relation_model.update(filter, nil, nil)
            end
          else #delete
            #p 'delete'
            res = relation_model.update(nil, nil, filter)
            if filter2
              res2 = relation_model.update(nil, nil, filter2)
              res = res or res2
            end
          end
        end
      end
    end
    res
  end

  def self.time_to_str(val, time_now=nil)
    time_now ||= Time.now
    min_ago = (time_now.to_i - val.to_i) / 60
    if min_ago < 0
      val = val.strftime('%d.%m.%Y')
    elsif min_ago == 0
      val = _('just now')
    elsif min_ago == 1
      val = _('a min. ago')
    else
      vals = time_now.to_a
      y, m, d = [vals[5], vals[4], vals[3]]  #current day
      midnight = Time.local(y, m, d)

      if (min_ago <= 90) and ((val >= midnight) or (min_ago <= 10))
        val = min_ago.to_s + ' ' + _('min. ago')
      elsif val >= midnight
        val = _('today')+' '+val.strftime('%R')
      elsif val.to_i >= (midnight.to_i-24*3600)  #last midnight
        val = _('yester')+' '+val.strftime('%R')
      else
        val = val.strftime('%d.%m.%y %R')
      end
    end
    val
  end

  def self.val_to_view(val, type, view, can_edit=true)
    color = nil
    if val and view
      if view=='date'
        if val.is_a? Integer
          val = Time.at(val)
          if can_edit
            val = val.strftime('%d.%m.%Y')
          else
            val = val.strftime('%d.%m.%y')
          end
          color = '#551111'
        end
      elsif view=='time'
        if val.is_a? Integer
          val = Time.at(val)
          if can_edit
            val = val.strftime('%d.%m.%Y %R')
          else
            val = time_to_str(val)
          end
          color = '#338833'
        end
      elsif view=='base64'
        val = val.to_s
        if $ruby_low19 or (not type) or (type=='text')
          val = Base64.encode64(val)
        else
          val = Base64.strict_encode64(val)
        end
        color = 'brown'
      elsif view=='phash'
        if val.is_a? String
          if can_edit
            val = PandoraKernel.bytes_to_hex(val)
            color = 'dark blue'
          else
            val = PandoraKernel.bytes_to_hex(val[2,16])
            color = 'blue'
          end
        end
      elsif view=='panhash'
        if val.is_a? String
          if can_edit
            val = PandoraKernel.bytes_to_hex(val)
          else
            val = PandoraKernel.bytes_to_hex(val[0,2])+' '+PandoraKernel.bytes_to_hex(val[2,16])
          end
          color = 'navy'
        end
      elsif view=='hex'
        #val = val.to_i
        val = PandoraKernel.bigint_to_bytes(val) if val.is_a? Integer
        val = PandoraKernel.bytes_to_hex(val)
        #end
        color = 'dark blue'
      elsif not can_edit and (view=='text')
        val = val[0,50].gsub(/[\r\n\t]/, ' ').squeeze(' ')
        val = val.rstrip
        color = '#226633'
      end
    end
    val ||= ''
    val = val.to_s
    [val, color]
  end

  def self.view_to_val(val, type, view)
    #p '---val1='+val.inspect
    val = nil if val==''
    if val and view
      case view
        when 'date', 'time'
          begin
            val = Time.parse(val)  #Time.strptime(defval, '%d.%m.%Y')
            val = val.to_i
          rescue
            val = 0
          end
        when 'base64'
          if $ruby_low19 or (not type) or (type=='Text')
            val = Base64.decode64(val)
          else
            val = Base64.strict_decode64(val)
          end
          color = 'brown'
        when 'hex', 'panhash', 'phash'
          #p 'type='+type.inspect
          if (['Bigint', 'Panhash', 'String', 'Blob', 'Text'].include? type) or (type[0,7]=='Panhash')
            #val = AsciiString.new(PandoraKernel.bigint_to_bytes(val))
            val = PandoraKernel.hex_to_bytes(val)
          else
            val = val.to_i(16)
          end
      end
    end
    val
  end

  # Panobject state flages
  # RU: Флаги состояния объекта
  PSF_Support   = 1

  # View and edit record dialog
  # RU: Окно просмотра и правки записи
  def self.act_panobject(tree_view, action)

    def self.get_panobject_icon(panobj)
      panobj_icon = nil
      ind = nil
      $notebook.children.each do |child|
        if child.name==panobj.ider
          ind = $notebook.children.index(child)
          break
        end
      end
      if ind
        first_lab_widget = $notebook.get_tab_label($notebook.children[ind]).children[0]
        if first_lab_widget.is_a? Gtk::Image
          image = first_lab_widget
          panobj_icon = $window.render_icon(image.stock, Gtk::IconSize::MENU).dup
        end
      end
      panobj_icon
    end

    path, column = tree_view.cursor
    new_act = action == 'Create'
    if path or new_act
      panobject = tree_view.panobject
      store = tree_view.model
      iter = nil
      sel = nil
      id = nil
      panhash0 = nil
      lang = 5
      panstate = 0
      created0 = nil
      creator0 = nil
      if path and (not new_act)
        iter = store.get_iter(path)
        id = iter[0]
        sel = panobject.select('id='+id.to_s, true)
        #p 'panobject.namesvalues='+panobject.namesvalues.inspect
        #p 'panobject.matter_fields='+panobject.matter_fields.inspect
        panhash0 = panobject.namesvalues['panhash']
        lang = panhash0[1].ord if panhash0 and panhash0.size>1
        lang ||= 0
        #panhash0 = panobject.panhash(sel[0], lang)
        panstate = panobject.namesvalues['panstate']
        panstate ||= 0
        if (panobject.is_a? PandoraModel::Created)
          created0 = panobject.namesvalues['created']
          creator0 = panobject.namesvalues['creator']
          #p 'created0, creator0='+[created0, creator0].inspect
        end
      end
      #p sel

      panobjecticon = get_panobject_icon(panobject)

      if action=='Delete'
        if id and sel[0]
          info = panobject.show_panhash(panhash0) #.force_encoding('ASCII-8BIT') ASCII-8BIT
          dialog = Gtk::MessageDialog.new($window, Gtk::Dialog::MODAL | Gtk::Dialog::DESTROY_WITH_PARENT,
            Gtk::MessageDialog::QUESTION,
            Gtk::MessageDialog::BUTTONS_OK_CANCEL,
            _('Record will be deleted. Sure?')+"\n["+info+']')
          dialog.title = _('Deletion')+': '+panobject.sname
          dialog.default_response = Gtk::Dialog::RESPONSE_OK
          dialog.icon = panobjecticon if panobjecticon
          if dialog.run == Gtk::Dialog::RESPONSE_OK
            res = panobject.update(nil, nil, 'id='+id.to_s)
            tree_view.sel.delete_if {|row| row[0]==id }
            store.remove(iter)
            #iter.next!
            pt = path.indices[0]
            pt = tree_view.sel.size-1 if pt>tree_view.sel.size-1
            tree_view.set_cursor(Gtk::TreePath.new(pt), column, false)
          end
          dialog.destroy
        end
      elsif action=='Dialog'
        show_talk_dialog(panhash0)
      else  # Edit or Insert

        edit = ((not new_act) and (action != 'Copy'))

        i = 0
        formfields = panobject.def_fields.clone
        tab_flds = panobject.tab_fields
        formfields.each do |field|
          val = nil
          fid = field[FI_Id]
          col = tab_flds.index{ |tf| tf[0] == fid }

          val = sel[0][col] if col and sel and sel[0].is_a? Array
          type = field[FI_Type]
          view = field[FI_View]

          val, color = val_to_view(val, type, view, true)
          field[FI_Value] = val
          field[FI_Color] = color
        end

        dialog = FieldsDialog.new(panobject, formfields, panobject.sname)
        dialog.icon = panobjecticon if panobjecticon

        if edit
          pub_exist = act_relation(nil, panhash0, RK_MaxPublic, :check)
          #count, rate, querist_rate = rate_of_panobj(panhash0)
          trust = nil
          res = trust_of_panobject(panhash0)
          trust = res if res.is_a? Float
          dialog.vouch_btn.active = (res != nil)
          dialog.vouch_btn.inconsistent = (res.is_a? Integer)
          dialog.trust_scale.sensitive = (trust != nil)
          #dialog.trust_scale.signal_emit('value-changed')
          trust ||= 0.0
          dialog.trust_scale.value = trust

          dialog.support_btn.active = (PSF_Support & panstate)>0
          dialog.public_btn.active = pub_exist
          dialog.public_btn.inconsistent = (pub_exist==nil)

          dialog.lang_entry.entry.text = lang.to_s if lang

          #dialog.lang_entry.active_text = lang.to_s
          #trust_lab = dialog.trust_btn.children[0]
          #trust_lab.modify_fg(Gtk::STATE_NORMAL, Gdk::Color.parse('#777777')) if signed == 1
        else
          key = current_key(false, false)
          not_key_inited = (not (key and key[KV_Obj]))
          dialog.support_btn.active = true
          dialog.vouch_btn.active = true
          if not_key_inited
            dialog.vouch_btn.inconsistent = true
            dialog.trust_scale.sensitive = false
          end
          dialog.public_btn.inconsistent = not_key_inited
        end

        st_text = panobject.panhash_formula
        st_text = st_text + ' [#'+panobject.panhash(sel[0], lang, true, true)+']' if sel and sel.size>0
        PandoraGUI.set_statusbar_text(dialog.statusbar, st_text)

        if panobject.class==PandoraModel::Key
          mi = Gtk::MenuItem.new("Действия")
          menu = Gtk::MenuBar.new
          menu.append(mi)

          menu2 = Gtk::Menu.new
          menuitem = Gtk::MenuItem.new("Генерировать")
          menu2.append(menuitem)
          mi.submenu = menu2
          #p dialog.action_area
          dialog.hbox.pack_end(menu, false, false)
          #dialog.action_area.add(menu)
        end

        titadd = nil
        if not edit
        #  titadd = _('edit')
        #else
          titadd = _('new')
        end
        dialog.title += ' ('+titadd+')' if titadd and (titadd != '')

        dialog.run do
          # take value from form
          dialog.fields.each do |field|
            entry = field[FI_Widget]
            field[FI_Value] = entry.text
          end
          dialog.text_fields.each do |field|
            textview = field[FI_Widget]
            field[FI_Value] = textview.buffer.text
          end

          # fill hash of values
          flds_hash = {}
          dialog.fields.each do |field|
            type = field[FI_Type]
            view = field[FI_View]
            val = field[FI_Value]

            val = view_to_val(val, type, view)
            flds_hash[field[FI_Id]] = val
          end
          dialog.text_fields.each do |field|
            flds_hash[field[FI_Id]] = field[FI_Value]
          end
          lg = nil
          begin
            lg = dialog.lang_entry.entry.text
            lg = lg.to_i if (lg != '')
          rescue
          end
          lang = lg if lg
          lang = 5 if (not lang.is_a? Integer) or (lang<0) or (lang>255)

          time_now = Time.now.to_i
          if (panobject.is_a? PandoraModel::Created)
            flds_hash['created'] = created0 if created0
            if not edit
              flds_hash['created'] = time_now
              creator = current_user_or_key(true)
              flds_hash['creator'] = creator
            end
          end
          flds_hash['modified'] = time_now
          panstate = 0
          panstate = panstate | PSF_Support if dialog.support_btn.active?
          flds_hash['panstate'] = panstate
          if (panobject.is_a? PandoraModel::Key)
            lang = flds_hash['rights'].to_i
          end

          panhash = panobject.panhash(flds_hash, lang)
          flds_hash['panhash'] = panhash

          if (panobject.is_a? PandoraModel::Key) and (flds_hash['kind'].to_i == KT_Priv) and edit
            flds_hash['panhash'] = panhash0
          end

          filter = nil
          filter = 'id='+id.to_s if edit
          res = panobject.update(flds_hash, nil, filter, true)
          if res
            filter ||= { :panhash => panhash, :modified => time_now }
            sel = panobject.select(filter, true)
            if sel[0]
              #p 'panobject.namesvalues='+panobject.namesvalues.inspect
              #p 'panobject.matter_fields='+panobject.matter_fields.inspect

              id = panobject.field_val('id', sel[0])  #panobject.namesvalues['id']
              id = id.to_i
              #p 'id='+id.inspect

              #p 'id='+id.inspect
              ind = tree_view.sel.index { |row| row[0]==id }
              #p 'ind='+ind.inspect
              if ind
                #p '---------CHANGE'
                tree_view.sel[ind] = sel[0]
                iter[0] = id
                store.row_changed(path, iter)
              else
                #p '---------INSERT'
                tree_view.sel << sel[0]
                iter = store.append
                iter[0] = id
                tree_view.set_cursor(Gtk::TreePath.new(tree_view.sel.size-1), nil, false)
              end

              if not dialog.vouch_btn.inconsistent?
                unsign_panobject(panhash0, true)
                if dialog.vouch_btn.active?
                  trust = (dialog.trust_scale.value*127).round
                  sign_panobject(panobject, trust)
                end
              end

              if not dialog.public_btn.inconsistent?
                #p 'panhash,panhash0='+[panhash, panhash0].inspect
                act_relation(nil, panhash0, RK_MaxPublic, :delete, true, true) if panhash != panhash0
                if dialog.public_btn.active?
                  act_relation(nil, panhash, RK_MaxPublic, :create, true, true)
                else
                  act_relation(nil, panhash, RK_MaxPublic, :delete, true, true)
                end
              end
            end
          end
        end
      end
    end
  end

  # Tree of panobjects
  # RU: Дерево субъектов
  class SubjTreeView < Gtk::TreeView
    attr_accessor :panobject, :sel
  end

  class SubjTreeViewColumn < Gtk::TreeViewColumn
    attr_accessor :tab_ind
  end

  # Tab box for notebook with image and close button
  # RU: Бокс закладки для блокнота с картинкой и кнопкой
  class TabLabelBox < Gtk::HBox
    attr_accessor :label

    def initialize(image, title, child=nil, *args)
      super(*args)
      label_box = self

      label_box.pack_start(image, false, false, 0) if image

      @label = Gtk::Label.new(title)

      label_box.pack_start(label, false, false, 0)

      if child
        btn = Gtk::Button.new
        btn.relief = Gtk::RELIEF_NONE
        btn.focus_on_click = false
        style = btn.modifier_style
        style.xthickness = 0
        style.ythickness = 0
        btn.modify_style(style)
        wim,him = Gtk::IconSize.lookup(Gtk::IconSize::MENU)
        btn.set_size_request(wim+2,him+2)
        btn.signal_connect('clicked') do |*args|
          yield if block_given?
          $notebook.remove_page($notebook.children.index(child))
          label_box.destroy if not label_box.destroyed?
          child.destroy if not child.destroyed?
        end
        close_image = Gtk::Image.new(Gtk::Stock::CLOSE, Gtk::IconSize::MENU)
        btn.add(close_image)

        align = Gtk::Alignment.new(1.0, 0.5, 0.0, 0.0)
        align.add(btn)
        label_box.pack_start(align, false, false, 0)
      end

      label_box.spacing = 3
      label_box.show_all
    end

  end

  # Showing panobject list
  # RU: Показ списка субъектов
  def self.show_panobject_list(panobject_class, widget=nil, sw=nil)
    single = (sw == nil)
    if single
      $notebook.children.each do |child|
        if child.name==panobject_class.ider
          $notebook.page = $notebook.children.index(child)
          return
        end
      end
    end
    panobject = panobject_class.new
    sel = panobject.select(nil, false, nil, panobject.sort)
    store = Gtk::ListStore.new(Integer)
    param_view_col = nil
    param_view_col = sel[0].size if panobject.ider=='Parameter'
    sel.each do |row|
      iter = store.append
      id = row[0].to_i
      iter[0] = id
      if param_view_col
        sel2 = panobject.select('id='+id.to_s, false, 'type, setting')
        type = sel2[0][0]
        setting = sel2[0][1]
        ps = decode_param_setting(setting)
        view = ps['view']
        view ||= pantype_to_view(type)
        row[param_view_col] = view
      end
    end
    treeview = SubjTreeView.new(store)
    treeview.name = panobject.ider
    treeview.panobject = panobject
    treeview.sel = sel
    tab_flds = panobject.tab_fields
    def_flds = panobject.def_fields
    def_flds.each do |df|
      id = df[FI_Id]
      tab_ind = tab_flds.index{ |tf| tf[0] == id }
      if tab_ind
        renderer = Gtk::CellRendererText.new
        #renderer.background = 'red'
        #renderer.editable = true
        #renderer.text = 'aaa'

        title = df[FI_VFName]
        title ||= v
        column = SubjTreeViewColumn.new(title, renderer )  #, {:text => i}

        #p v
        #p ind = panobject.def_fields.index_of {|f| f[0]==v }
        #p fld = panobject.def_fields[ind]

        column.tab_ind = tab_ind
        #column.sort_column_id = ind
        #p column.ind = i
        #p column.fld = fld
        #panhash_col = i if (v=='panhash')
        column.resizable = true
        column.reorderable = true
        column.clickable = true
        treeview.append_column(column)
        column.signal_connect('clicked') do |col|
          p 'sort clicked'
        end
        column.set_cell_data_func(renderer) do |tvc, renderer, model, iter|
          color = 'black'
          col = tvc.tab_ind
          panobject = tvc.tree_view.panobject
          row = tvc.tree_view.sel[iter.path.indices[0]]
          val = row[col] if row
          if val
            fdesc = panobject.tab_fields[col][TI_Desc]
            if fdesc.is_a? Array
              view = nil
              if param_view_col and (fdesc[FI_Id]=='value')
                view = row[param_view_col] if row
              else
                view = fdesc[FI_View]
              end
              val, color = val_to_view(val, nil, view, false)
            else
              val = val.to_s
            end
            if $jcode_on
              val = val[/.{0,#{45}}/m]
            else
              val = val[0,45]
            end
          else
            val = ''
          end
          renderer.foreground = color
          renderer.text = val
        end
      end
    end
    treeview.signal_connect('row_activated') do |tree_view, path, column|
      act_panobject(tree_view, 'Edit')
    end

    sw ||= Gtk::ScrolledWindow.new(nil, nil)
    sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
    sw.name = panobject.ider
    sw.add(treeview)
    sw.border_width = 0;

    if single
      if widget.is_a? Gtk::ImageMenuItem
        animage = widget.image
      elsif widget.is_a? Gtk::ToolButton
        animage = widget.icon_widget
      else
        animage = nil
      end
      image = nil
      if animage
        image = Gtk::Image.new(animage.stock, Gtk::IconSize::MENU)
        image.set_padding(2, 0)
      end

      label_box = TabLabelBox.new(image, panobject.pname, sw, false, 0) do
        store.clear
        treeview.destroy
      end

      page = $notebook.append_page(sw, label_box)
      sw.show_all
      $notebook.page = $notebook.n_pages-1

      if treeview.sel.size>0
        treeview.set_cursor(Gtk::TreePath.new(treeview.sel.size-1), nil, false)
      end
      treeview.grab_focus
    end

    menu = Gtk::Menu.new
    menu.append(create_menu_item(['Create', Gtk::Stock::NEW, _('Create'), 'Insert']))
    menu.append(create_menu_item(['Edit', Gtk::Stock::EDIT, _('Edit'), 'Return']))
    menu.append(create_menu_item(['Delete', Gtk::Stock::DELETE, _('Delete'), 'Delete']))
    menu.append(create_menu_item(['Copy', Gtk::Stock::COPY, _('Copy'), '<control>Insert']))
    menu.append(create_menu_item(['-', nil, nil]))
    menu.append(create_menu_item(['Dialog', Gtk::Stock::MEDIA_PLAY, _('Dialog'), '<control>D']))
    menu.append(create_menu_item(['Opinion', Gtk::Stock::JUMP_TO, _('Opinions'), '<control>BackSpace']))
    menu.append(create_menu_item(['Connect', Gtk::Stock::CONNECT, _('Connect'), '<control>N']))
    menu.append(create_menu_item(['Relate', Gtk::Stock::INDEX, _('Relate'), '<control>R']))
    menu.append(create_menu_item(['-', nil, nil]))
    menu.append(create_menu_item(['Clone', Gtk::Stock::CONVERT, _('Recreate the table')]))
    menu.show_all

    treeview.add_events(Gdk::Event::BUTTON_PRESS_MASK)
    treeview.signal_connect('button_press_event') do |widget, event|
      if (event.button == 3)
        menu.popup(nil, nil, event.button, event.time)
      end
    end
  end

  $hunter_count   = 0
  $listener_count = 0
  $fisher_count   = 0
  def self.update_conn_status(conn, hunter, diff_count)
    if hunter
      $hunter_count += diff_count
    else
      $listener_count += diff_count
    end
    set_status_field(SF_Conn, $hunter_count.to_s+'/'+$listener_count.to_s+'/'+$fisher_count.to_s)
  end

  $connections = []

  def self.add_connection(conn)
    if not $connections.include?(conn)
      #Thread.critical = true
      $connections << conn
      #Thread.critical = false
      update_conn_status(conn, (conn.conn_mode & CM_Hunter)>0, 1)
    end
  end

  def self.del_connection(conn)
    #Thread.critical = true
    if $connections.delete(conn)
      #Thread.critical = false
      update_conn_status(conn, (conn.conn_mode & CM_Hunter)>0, -1)
    else
      #Thread.critical = false
    end
  end

  def self.connection_of_node(node)
    host, port, proto = decode_node(node)
    connection = $connections.find do |e|
      (e.is_a? Connection) and ((e.host_ip == host) or (e.host_name == host)) and (e.port == port) \
        and (e.proto == proto)
    end
    connection
  end

  def self.connection_of_dialog(dialog)
    connection = $connections.find { |e| (e.dialog == dialog) }
    connection
  end

  # Network exchange comands
  # RU: Команды сетевого обмена
  EC_Media     = 0     # Медиа данные
  EC_Init      = 1     # Инициализация диалога (версия протокола, сжатие, авторизация, шифрование)
  EC_Message   = 2     # Мгновенное текстовое сообщение
  EC_Channel   = 3     # Запрос открытия медиа-канала
  EC_Query     = 4     # Запрос пачки сортов или пачки панхэшей
  EC_News      = 5     # Пачка сортов или пачка панхэшей измененных записей
  EC_Request   = 6     # Запрос записи/патча/миниатюры
  EC_Record    = 7     # Выдача записи
  EC_Patch     = 8     # Выдача патча
  EC_Preview   = 9     # Выдача миниатюры
  EC_Fishing   = 10    # Управление рыбалкой
  EC_Pipe      = 11    # Данные канала двух рыбаков
  EC_Sync      = 12    # Последняя команда в серии, или индикация "живости"
  EC_Wait      = 250   # Временно недоступен
  EC_More      = 251   # Давай дальше
  EC_Bye       = 252   # Рассоединение
  EC_Data      = 253   # Ждем данные
  #EC_Notice    = 5
  #EC_Pack      = 7

  TExchangeCommands = {EC_Init=>'init', EC_Query=>'query', EC_News=>'news',
    EC_Patch=>'patch', EC_Request=>'request', EC_Record=>'record', EC_Pipe=>'pipe',
    EC_Wait=>'wait', EC_More=>'more', EC_Bye=>'bye'}
  TExchangeCommands_invert = TExchangeCommands.invert

  # RU: Преобразует код в xml-команду
  def self.cmd_to_text(cmd)
    TExchangeCommands[cmd]
  end

  # RU: Преобразует xml-команду в код
  def self.text_to_cmd(text)
    TExchangeCommands_invert[text.downcase]
  end

  QI_ReadInd    = 0
  QI_WriteInd   = 1
  QI_QueueInd   = 2

  # Init empty queue. Poly read is possible
  # RU: Создание пустой очереди. Возможно множественное чтение
  def self.init_empty_queue(poly_read=false)
    res = Array.new
    if poly_read
      res[QI_ReadInd] = Array.new  # will be array of read pointers
    else
      res[QI_ReadInd] = -1
    end
    res[QI_WriteInd] = -1
    res[QI_QueueInd] = Array.new
    res
  end

  MaxQueue = 20

  # Add block to queue
  # RU: Добавить блок в очередь
  def self.add_block_to_queue(queue, block, max=MaxQueue)
    res = false
    if block
      ind = queue[QI_WriteInd]
      if ind<max
        ind += 1
      else
        ind = 0
      end
      queue[QI_WriteInd] = ind
      queue[QI_QueueInd][ind] = block
      res = true
    else
      puts 'add_block_to_queue: Block cannot be nil'
    end
    res
  end

  QS_Empty     = 0
  QS_NotEmpty  = 1
  QS_Full      = 2

  def self.get_queue_state(queue, max=MaxQueue, ptrind=nil)
    res = QS_NotEmpty
    ind = queue[QI_ReadInd]
    if ptrind
      ind = ind[ptrind]
      ind ||= -1
    end
    if ind == queue[QI_WriteInd]
      res = QS_Empty
    else
      if ind<max
        ind += 1
      else
        ind = 0
      end
      res = QS_Full if ind == queue[QI_WriteInd]
    end
    res
  end

  # Get block from queue (set "ptrind" like 0,1,2..)
  # RU: Взять блок из очереди (задавай "ptrind" как 0,1,2..)
  def self.get_block_from_queue(queue, max=MaxQueue, ptrind=nil)
    block = nil
    if queue
      pointers = nil
      ind = queue[QI_ReadInd]
      if ptrind
        pointers = ind
        ind = pointers[ptrind]
        ind ||= -1
      end
      if ind != queue[QI_WriteInd]
        if ind<max
          ind += 1
        else
          ind = 0
        end
        block = queue[QI_QueueInd][ind]
        if ptrind
          pointers[ptrind] = ind
        else
          queue[QI_ReadInd] = ind
        end
      end
    end
    block
  end

  $media_buf_size = 50
  $send_media_queue = []
  $send_media_rooms = nil

  def self.set_send_ptrind_by_room(room_id)
    $send_media_rooms ||= {}
    ptr = nil
    if room_id
      ptr = $send_media_rooms[room_id]
      if ptr
        ptr[0] = true
        ptr = ptr[1]
      else
        ptr = $send_media_rooms.size
        $send_media_rooms[room_id] = [true, ptr]
      end
    end
    ptr
  end

  def self.nil_send_ptrind_by_room(room_id)
    $send_media_rooms ||= {}
    if room_id
      ptr = $send_media_rooms[room_id]
      if ptr
        ptr[0] = false
      end
    end
    res = $send_media_rooms.select{|k,v| v[0]}
    res.size
  end

  $max_opened_keys = 1000
  $open_keys = {}

  def self.open_key(panhash, models, init=true)
    key_vec = nil
    if panhash.is_a? String
      key_vec = $open_keys[panhash]
      #p 'openkey key='+key_vec.inspect+' $open_keys.size='+$open_keys.size.inspect
      if key_vec
        key_vec[KV_Trust] = trust_of_panobject(panhash)
      elsif ($open_keys.size<$max_opened_keys)
        model = PandoraGUI.model_gui('Key', models)
        filter = {:panhash => panhash}
        sel = model.select(filter, false)
        #p 'openkey sel='+sel.inspect
        if (sel.is_a? Array) and (sel.size>0)
          sel.each do |row|
            kind = model.field_val('kind', row)
            type, klen = divide_type_and_klen(kind)
            if type != KT_Priv
              cipher = model.field_val('cipher', row)
              pub = model.field_val('body', row)
              creator = model.field_val('creator', row)

              key_vec = []
              key_vec[KV_Key1] = pub
              key_vec[KV_Kind] = kind
              #key_vec[KV_Pass] = passwd
              key_vec[KV_Panhash] = panhash
              key_vec[KV_Creator] = creator
              key_vec[KV_Trust] = trust_of_panobject(panhash)

              $open_keys[panhash] = key_vec
              break
            end
          end
        else
          key_vec = 0
        end
      end
    else
      key_vec = panhash
    end
    if init and key_vec and (not key_vec[KV_Obj])
      key_vec = init_key(key_vec)
      #p 'openkey init key='+key_vec.inspect
    end
    key_vec
  end

  def self.find_sha1_solution(phrase)
    res = nil
    lenbit = phrase[phrase.size-1].ord
    len = lenbit/8
    puzzle = phrase[0, len]
    tailbyte = nil
    drift = lenbit - len*8
    if drift>0
      tailmask = 0xFF >> (8-drift)
      tailbyte = (phrase[len].ord & tailmask) if tailmask>0
    end
    i = 0
    while (not res) and (i<0xFFFFFFFF)
      add = PandoraKernel.bigint_to_bytes(i)
      hash = Digest::SHA1.digest(phrase+add)
      offer = hash[0, len]
      if (offer==puzzle) and ((not tailbyte) or ((hash[len].ord & tailmask)==tailbyte))
        res = add
      end
      i += 1
    end
    res
  end

  def self.check_sha1_solution(phrase, add)
    res = false
    lenbit = phrase[phrase.size-1].ord
    len = lenbit/8
    puzzle = phrase[0, len]
    tailbyte = nil
    drift = lenbit - len*8
    if drift>0
      tailmask = 0xFF >> (8-drift)
      tailbyte = (phrase[len].ord & tailmask) if tailmask>0
    end
    hash = Digest::SHA1.digest(phrase+add)
    offer = hash[0, len]
    if (offer==puzzle) and ((not tailbyte) or ((hash[len].ord & tailmask)==tailbyte))
      res = true
    end
    res
  end

  CapSymbols = '123456789qertyupasdfghkzxvbnmQRTYUPADFGHJKLBNM'
  CapFonts = ['Sans', 'Arial', 'Times', 'Verdana', 'Tahoma']

  def self.generate_captcha(drawing=nil, length=6, height=70, circles=5, curves=0)

    def self.show_char(c, cr, x0, y0, step)
      #cr.set_font_size(0.3+0.1*rand)
      size = 0.36
      size = 0.38 if ('a'..'z').include? c
      cr.set_font_size(size*(0.7+0.3*rand))
      cr.select_font_face(CapFonts[rand(CapFonts.size)], Cairo::FONT_SLANT_NORMAL, Cairo::FONT_WEIGHT_NORMAL)
      x = x0 + step + 0.2*(rand-0.5)
      y = y0 + 0.1 + 0.3*(rand-0.5)
      cr.move_to(x, y)
      cr.show_text(c)
      cr.stroke
      [x, y]
    end

    def self.show_blur(cr, x0, y0, r)
      cr.close_path
      x, y = [x0, y0]
      #cr.move_to(x, y)
      x1, y1 = x0+1.0*rand*r, y0-0.5*rand*r
      cr.curve_to(x0, y0, x0, y1, x1, y1)
      x2, y2 = x0-1.0*rand*r, y0+0.5*rand-r
      cr.curve_to(x1, y1, x1, y2, x2, y2)
      x3, y3 = x0+1.0*rand*r, y0+0.5*rand-r
      cr.curve_to(x2, y2, x3, y2, x3, y3)
      cr.curve_to(x3, y3, x0, y3, x0, y0)
      cr.stroke
    end

    width = height*2
    if not drawing
      drawing = Gdk::Pixmap.new(nil, width, height, 24)
    end

    cr = drawing.create_cairo_context
    #cr.scale(*widget.window.size)
    cr.scale(height, height)
    cr.set_line_width(0.03)

    cr.set_source_color(Gdk::Color.new(65535, 65535, 65535))
    cr.gdk_rectangle(Gdk::Rectangle.new(0, 0, 2, 1))
    cr.fill

    text = ''
    length.times do
      text << CapSymbols[rand(CapSymbols.size)]
    end
    cr.set_source_rgba(0.0, 0.0, 0.0, 1.0)

    extents = cr.text_extents(text)
    step = 2.0/(text.bytesize+2.0)
    x = 0.0
    y = 0.5

    text.each_char do |c|
      x, y2 = show_char(c, cr, x, y, step)
    end

    cr.set_source_rgba(0.0, 0.0, 0.0, 1.0)

    circles.times do
      x = 0.1+rand(20)/10.0
      y = 0.1+rand(10)/12.0
      r = 0.05+rand/12.0
      f = 2.0*Math::PI * rand
      cr.arc(x, y, r, f, f+(2.2*Math::PI * rand))
      cr.stroke
    end
    curves.times do
      x = 0.1+rand(20)/10.0
      y = 0.1+rand(10)/10.0
      r = 0.3+rand/10.0
      show_blur(cr, x, y, r)
    end

    pixbuf = Gdk::Pixbuf.from_drawable(nil, drawing, 0, 0, width, height)
    buf = pixbuf.save_to_buffer('jpeg')
    [text, buf]
  end

  def self.get_exchage_params
    $incoming_addr       = PandoraGUI.get_param('incoming_addr')
    $puzzle_bit_length   = PandoraGUI.get_param('puzzle_bit_length')
    $puzzle_sec_delay    = PandoraGUI.get_param('puzzle_sec_delay')
    $captcha_length      = PandoraGUI.get_param('captcha_length')
    $captcha_attempts    = PandoraGUI.get_param('captcha_attempts')
    $trust_for_captchaed = PandoraGUI.get_param('trust_for_captchaed')
    $trust_for_listener  = PandoraGUI.get_param('trust_for_listener')
  end

  PK_Key    = 221

  def self.get_record_by_panhash(kind, panhash, with_kind=true, models=nil, get_pson=true)
    res = nil
    panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
    model = model_gui(panobjectclass.ider, models)
    filter = {'panhash'=>panhash}
    if kind==PK_Key
      filter['kind'] = 0x81
    end
    getfields = nil
    getfields = 'id' if not get_pson
    sel = model.select(filter, true, getfields, nil, 1)
    if sel and sel.size>0
      if get_pson
        #namesvalues = panobject.namesvalues
        #fields = model.matter_fields
        fields = model.clear_excess_fields(sel[0])
        p 'get_rec: matter_fields='+fields.inspect
        # need get all fields (except: id, panhash, modified) + kind
        lang = PandoraKernel.lang_from_panhash(panhash)
        res = AsciiString.new
        res << [kind].pack('C') if with_kind
        res << [lang].pack('C')
        p 'get_record_by_panhash|||  fields='+fields.inspect
        res << namehash_to_pson(fields)
      else
        res = true
      end
    end
    res
  end

  def self.save_record(kind, lang, values, models=nil)
    res = false
    p '=======save_record  [kind, lang, values]='+[kind, lang, values].inspect
    panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
    model = model_gui(panobjectclass.ider, models)
    panhash = model.panhash(values, lang)
    p 'panhash='+panhash.inspect

    filter = {'panhash'=>panhash}
    if kind==PK_Key
      filter['kind'] = 0x81
    end
    sel = model.select(filter, true, nil, nil, 1)
    if sel and (sel.size>0)
      res = true
    else
      values['panhash'] = panhash
      values['modified'] = Time.now.to_i
      res = model.update(values, nil, nil)
    end
    res
  end

  $base_id = ''

  MaxPackSize = 1500
  MaxSegSize  = 1200
  CommSize = 6
  CommExtSize = 10

  ECC_Init_Hello       = 0
  ECC_Init_Puzzle      = 1
  ECC_Init_Phrase      = 2
  ECC_Init_Sign        = 3
  ECC_Init_Captcha     = 4
  ECC_Init_Answer      = 5

  ECC_Query0_Kinds      = 0
  ECC_Query255_AllChanges =255

  ECC_News0_Kinds       = 0

  ECC_Channel0_Open     = 0
  ECC_Channel1_Opened   = 1
  ECC_Channel2_Close    = 2
  ECC_Channel3_Closed   = 3
  ECC_Channel4_Fail     = 4

  ECC_Sync10_Encode     = 10

  ECC_More_NoRecord     = 1

  ECC_Bye_Exit          = 200
  ECC_Bye_Unknown       = 201
  ECC_Bye_BadCommCRC    = 202
  ECC_Bye_BadCommLen    = 203
  ECC_Bye_BadCRC        = 204
  ECC_Bye_DataTooLong   = 205
  ECC_Wait_NoHandlerYet = 206

  # Режимы чтения
  RM_Comm      = 0   # Базовая команда
  RM_CommExt   = 1   # Расширение команды для нескольких сегментов
  RM_SegLenN   = 2   # Длина второго (и следующих) сегмента в серии
  RM_SegmentS  = 3   # Чтение одиночного сегмента
  RM_Segment1  = 4   # Чтение первого сегмента среди нескольких
  RM_SegmentN  = 5   # Чтение второго (и следующих) сегмента в серии

  # Connection mode
  # RU: Режим соединения
  CM_Hunter       = 1

  # Connected state
  # RU: Состояние соединения
  CS_Connecting    = 0
  CS_Connected     = 1
  CS_Stoping       = 2
  CS_StopRead      = 3
  CS_Disconnected  = 4

  # Stage of exchange
  # RU: Стадия обмена
  ST_Begin        = 0
  ST_IpCheck      = 1
  ST_Protocol     = 3
  ST_Puzzle       = 4
  ST_Sign         = 5
  ST_Captcha      = 6
  ST_Greeting     = 7
  ST_Exchange     = 8

  # Connection state flags
  # RU: Флаги состояния соединения
  CSF_Message     = 1
  CSF_Messaging   = 2

  # Address types
  # RU: Типы адресов
  AT_Ip4        = 0
  AT_Ip6        = 1
  AT_Hyperboria = 2
  AT_Netsukuku  = 3

  # Inquirer steps
  # RU: Шаги почемучки
  IS_CreatorCheck  = 0
  IS_Finished      = 255

  $incoming_addr = nil
  $puzzle_bit_length = 0  #8..24  (recommended 14)
  $puzzle_sec_delay = 2   #0..255 (recommended 2)
  $captcha_length = 4     #4..8   (recommended 6)
  $captcha_attempts = 2
  $trust_for_captchaed = true
  $trust_for_listener = true

  class Connection
    attr_accessor :host_name, :host_ip, :port, :proto, :node, :conn_mode, :conn_state, :stage, :dialog, \
      :send_thread, :read_thread, :socket, :read_state, :send_state, :read_mes, :read_media,
      :send_models, :recv_models, \
      :read_req, :send_mes, :send_media, :send_req, :sindex, :rindex, :read_queue, :send_queue, :params,
      :rcmd, :rcode, :rdata, :scmd, :scode, :sbuf, :last_scmd, :log_mes, :skey, :rkey, :s_encode, :r_encode,
      :media_send, :node_id, :node_panhash, :entered_captcha, :captcha_sw

    def initialize(ahost_name, ahost_ip, aport, aproto, node, aconn_mode=0, aconn_state=CS_Disconnected, \
    anode_id=nil)
      super()
      @stage         = ST_Protocol  #ST_IpCheck
      @host_name     = ahost_name
      @host_ip       = ahost_ip
      @port          = aport
      @proto         = aproto
      @node          = node
      @conn_mode     = aconn_mode
      @conn_state    = aconn_state
      @read_state     = 0
      @send_state     = 0
      @sindex         = 0
      @rindex         = 0
      @read_mes       = PandoraGUI.init_empty_queue
      @read_media     = PandoraGUI.init_empty_queue
      @read_req       = PandoraGUI.init_empty_queue
      @send_mes       = PandoraGUI.init_empty_queue
      @send_media     = PandoraGUI.init_empty_queue
      @send_req       = PandoraGUI.init_empty_queue
      @read_queue     = PandoraGUI.init_empty_queue
      @send_queue     = PandoraGUI.init_empty_queue
      @send_models    = {}
      @recv_models    = {}
      @params         = {}
      @media_send     = false
      @node_id        = anode_id
      @node_panhash   = nil
      #Thread.critical = true
      PandoraGUI.add_connection(self)
      #Thread.critical = false
    end

    def unpack_comm(comm)
      errcode = 0
      if comm.bytesize == CommSize
        index, cmd, code, segsign, crc8 = comm.unpack('CCCnC')
        crc8f = (index & 255) ^ (cmd & 255) ^ (code & 255) ^ (segsign & 255) ^ ((segsign >> 8) & 255)
        if crc8 != crc8f
          errcode = 1
        end
      else
        errcode = 2
      end
      [index, cmd, code, segsign, errcode]
    end

    def unpack_comm_ext(comm)
      if comm.bytesize == CommExtSize
        datasize, fullcrc32, segsize = comm.unpack('NNn')
      else
        log_message(LM_Error, 'Ошибочная длина расширения команды')
      end
      [datasize, fullcrc32, segsize]
    end

    LONG_SEG_SIGN   = 0xFFFF

    # RU: Отправляет команду и данные, если есть !!! ДОБАВИТЬ !!! send_number!, buflen, buf
    def send_comm_and_data(index, cmd, code, data=nil)
      res = nil
      data ||= ''
      data = AsciiString.new(data)
      datasize = data.bytesize
      if datasize <= MaxSegSize
        segsign = datasize
        segsize = datasize
      else
        segsign = LONG_SEG_SIGN
        segsize = MaxSegSize
      end
      crc8 = (index & 255) ^ (cmd & 255) ^ (code & 255) ^ (segsign & 255) ^ ((segsign >> 8) & 255)
      # Команда как минимум равна 1+1+1+2+1= 6 байт (CommSize)
      #p 'SCAB: '+[index, cmd, code, segsign, crc8].inspect
      comm = AsciiString.new([index, cmd, code, segsign, crc8].pack('CCCnC'))
      if index<255 then index += 1 else index = 0 end
      buf = AsciiString.new
      if datasize>0
        if segsign == LONG_SEG_SIGN
          fullcrc32 = Zlib.crc32(data)
          # если пакетов много, то добавить еще 4+4+2= 10 байт
          comm << [datasize, fullcrc32, segsize].pack('NNn')
          buf << data[0, segsize]
        else
          buf << data
        end
        segcrc32 = Zlib.crc32(buf)
        # в конце всегда CRC сегмента - 4 байта
        buf << [segcrc32].pack('N')
      end
      buf = comm + buf
      #p "!SEND: ("+buf+')'

      # tos_sip    cs3   0x60  0x18
      # tos_video  af41  0x88  0x22
      # tos_xxx    cs5   0xA0  0x28
      # tos_audio  ef    0xB8  0x2E
      if (not @media_send) and (cmd == EC_Media)
        @media_send = true
        socket.setsockopt(Socket::IPPROTO_IP, Socket::IP_TOS, 0xA0)  # QoS (VoIP пакет)
        p '@media_send = true'
      elsif @media_send and (cmd != EC_Media)
        @media_send = false
        socket.setsockopt(Socket::IPPROTO_IP, Socket::IP_TOS, 0)
        p '@media_send = false'
      end
      #if cmd == EC_Media
      #  if code==0
      #    p 'send AUDIO ('+buf.size.to_s+')'
      #  else
      #    p 'send VIDEO ('+buf.size.to_s+')'
      #  end
      #end
      begin
        if socket and not socket.closed?
          #sended = socket.write(buf)
          sended = socket.send(buf, 0)
        else
          sended = -1
        end
      rescue #Errno::ECONNRESET, Errno::ENOTSOCK, Errno::ECONNABORTED
        sended = -1
      end
      #socket.setsockopt(Socket::IPPROTO_IP, Socket::IP_TOS, 0x00)  # обычный пакет
      #p log_mes+'SEND_MAIN: ('+buf+')'

      if sended == buf.bytesize
        res = index
      elsif sended != -1
        log_message(LM_Error, 'Не все данные отправлены '+sended.to_s)
      end
      segindex = 0
      i = segsize
      while res and ((datasize-i)>0)
        segsize = datasize-i
        segsize = MaxSegSize if segsize>MaxSegSize
        if segindex<0xFFFFFFFF then segindex += 1 else segindex = 0 end
        comm = [index, segindex, segsize].pack('CNn')
        if index<255 then index += 1 else index = 0 end
        buf = data[i, segsize]
        buf << [Zlib.crc32(buf)].pack('N')
        buf = comm + buf
        begin
          if socket and not socket.closed?
            #sended = socket.write(buf)
            sended = socket.send(buf, 0)
          else
            sended = -1
          end
        rescue #Errno::ECONNRESET, Errno::ENOTSOCK, Errno::ECONNABORTED
          sended = -1
        end
        if sended == buf.bytesize
          res = index
          #p log_mes+'SEND_ADD: ('+buf+')'
        elsif sended != -1
          res = nil
          log_message(LM_Error, 'Не все данные отправлены2 '+sended.to_s)
        end
        i += segsize
      end
      res
    end

    # compose error command and add log message
    def err_scmd(mes=nil, code=nil, buf=nil)
      @scmd = EC_Bye
      if code
        @scode = code
      else
        @scode = rcmd
      end
      if buf
        @sbuf = buf
      elsif buf==false
        @sbuf = nil
      else
        logmes = '(rcmd=' + rcmd.to_s + '/' + rcode.to_s + ' stage=' + stage.to_s + ')'
        logmes = _(mes) + ' ' + logmes if mes and (mes.bytesize>0)
        @sbuf = logmes
        mesadd = ''
        mesadd = ' err=' + code.to_s if code
        log_message(LM_Warning, logmes+mesadd)
      end
    end

    # Add segment (chunk, grain, phrase) to pack and send when it's time
    # RU: Добавляет сегмент в пакет и отправляет если пора
    def add_send_segment(ex_comm, last_seg=true, param=nil, scode=nil)
      res = nil
      scmd = ex_comm
      scode ||= 0
      sbuf = nil
      case ex_comm
        when EC_Init
          @rkey = PandoraGUI.current_key(false, false)
          #p log_mes+'first key='+key.inspect
          if @rkey and @rkey[KV_Obj]
            key_hash = @rkey[KV_Panhash]
            scode = EC_Init
            scode = ECC_Init_Hello
            hparams = {:version=>0, :mode=>0, :mykey=>key_hash, :tokey=>nil}
            hparams[:addr] = $incoming_addr if $incoming_addr and (not ($incoming_addr != ''))
            sbuf = PandoraGUI.namehash_to_pson(hparams)
          else
            scmd = EC_Bye
            scode = ECC_Bye_Exit
            sbuf = nil
          end
        when EC_Message
          #mes = send_mes[2][buf_ind] #mes
          #if mes=='video:true:'
          #  scmd = EC_Channel
          #  scode = ECC_Channel0_Open
          #  chann = 1
          #  sbuf = [chann].pack('C')
          #elsif mes=='video:false:'
          #  scmd = EC_Channel
          #  scode = ECC_Channel2_Close
          #  chann = 1
          #  sbuf = [chann].pack('C')
          #else
          #  sbuf = mes
          #end
          sbuf = param
        #when EC_Media
        #  sbuf = param
        when EC_Bye
          scmd = EC_Bye
          scode = ECC_Bye_Exit
          sbuf = param
        else
          sbuf = param
      end
      #while PandoraGUI.get_queue_state(@send_queue) == QS_Full do
      #  p log_mes+'get_queue_state.EX = '+PandoraGUI.get_queue_state(@send_queue).inspect
      #  Thread.pass
      #end
      res = PandoraGUI.add_block_to_queue(@send_queue, [scmd, scode, sbuf])

      if scmd != EC_Media
        sbuf ||= '';
        p log_mes+'add_send_segment:  [scmd, scode, sbuf.bytesize]='+[scmd, scode, sbuf.bytesize].inspect
        p log_mes+'add_send_segment2: sbuf='+sbuf.inspect if sbuf
      end
      if not res
        puts 'add_send_segment: add_block_to_queue error'
        @conn_state == CS_Stoping
      end
      res
    end

    def set_request(panhashes, send_now=false)
      ascmd = EC_Request
      ascode = 0
      asbuf = nil
      if panhashes.is_a? Array
        asbuf = PandoraKernel.rubyobj_to_pson_elem(panhashes)
      else
        ascode = PandoraKernel.kind_from_panhash(panhashes)
        asbuf = panhashes[1..-1]
      end
      if send_now
        add_send_segment(ascmd, true, asbuf, ascode)
      else
        @scmd = ascmd
        @scode = ascode
        @sbuf = asbuf
      end
    end

    # Accept received segment
    # RU: Принять полученный сегмент
    def accept_segment

      def recognize_params
        hash = PandoraGUI.pson_to_namehash(rdata)
        if not hash
          err_scmd('Hello data is wrong')
        end
        if (rcmd == EC_Init) and (rcode == ECC_Init_Hello)
          params['version']  = hash['version']
          params['mode']     = hash['mode']
          params['addr']     = hash['addr']
          params['srckey']   = hash['mykey']
          params['dstkey']   = hash['tokey']
        end
        p log_mes+'RECOGNIZE_params: '+hash.inspect
        #p params['srckey']
      end

      def init_skey_or_error(first=true)
        def get_sphrase(init=false)
          phrase = params['sphrase'] if not init
          if init or (not phrase)
            phrase = OpenSSL::Random.random_bytes(256)
            params['sphrase'] = phrase
            init = true
          end
          [phrase, init]
        end
        skey_panhash = params['srckey']
        #p log_mes+'     skey_panhash='+skey_panhash.inspect
        if skey_panhash.is_a? String and (skey_panhash.bytesize>0)
          if first and (stage == ST_Protocol) and $puzzle_bit_length \
          and ($puzzle_bit_length>0) and ((conn_mode & CM_Hunter) == 0)
            phrase, init = get_sphrase(true)
            phrase[-1] = $puzzle_bit_length.chr
            phrase[-2] = $puzzle_sec_delay.chr
            @stage = ST_Puzzle
            @scode = ECC_Init_Puzzle
            @scmd  = EC_Init
            @sbuf = phrase
            params['puzzle_start'] = Time.now.to_i
          else
            @skey = PandoraGUI.open_key(skey_panhash, @recv_models, false)
            # key: 1) trusted and inited, 2) stil not trusted, 3) denied, 4) not found
            # or just 4? other later!
            if (@skey.is_a? Integer) and (@skey==0)
              set_request(skey_panhash)
            elsif @skey
              #phrase = PandoraKernel.bigint_to_bytes(phrase)
              @stage = ST_Sign
              @scode = ECC_Init_Phrase
              @scmd  = EC_Init
              phrase, init = get_sphrase(false)
              p log_mes+'send phrase len='+phrase.bytesize.to_s
              if init
                @sbuf = phrase
              else
                @sbuf = nil
              end
            else
              err_scmd('Key is invalid')
            end
          end
        else
          err_scmd('Key panhash is required')
        end
      end

      def send_captcha
        attempts = @skey[KV_Trust]
        p log_mes+'send_captcha:  attempts='+attempts.to_s
        if attempts<$captcha_attempts
          @skey[KV_Trust] = attempts+1
          @scmd = EC_Init
          @scode = ECC_Init_Captcha
          text, buf = PandoraGUI.generate_captcha(nil, $captcha_length)
          params['captcha'] = text.downcase
          clue_text = 'You may enter small letters|'+$captcha_length.to_s+'|'+PandoraGUI::CapSymbols
          clue_text = clue_text[0,255]
          @sbuf = [clue_text.bytesize].pack('C')+clue_text+buf
          @stage = ST_Captcha
        else
          err_scmd('Captcha attempts is exhausted')
        end
      end

      def update_node(skey_panhash=nil, sbase_id=nil, trust=nil, session_key=nil)
        node_model = PandoraGUI.model_gui('Node', @recv_models)
        state = 0
        sended = 0
        received = 0
        one_ip_count = 0
        bad_attempts = 0
        ban_time = 0
        time_now = Time.now.to_i
        panhash = nil
        key_hash = nil
        base_id = nil
        creator = nil
        created = nil

        readflds = 'id, state, sended, received, one_ip_count, bad_attempts,' \
           +'ban_time, panhash, key_hash, base_id, creator, created'

        #trusted = ((trust.is_a? Float) and (trust>0))
        filter = {:key_hash=>skey_panhash, :base_id=>sbase_id}
        #if not trusted
        #  filter[:addr_from] = host_ip
        #end
        sel = node_model.select(filter, false, readflds, nil, 1)
        if (not sel) or (sel.size==0) and @node_id
          filter = {:id=>@node_id}
          sel = node_model.select(filter, false, readflds, nil, 1)
        end

        if sel and sel.size>0
          row = sel[0]
          node_id = row[0]
          state = row[1]
          sended = row[2]
          received = row[3]
          one_ip_count = row[4]
          one_ip_count ||= 0
          bad_attempts = row[5]
          ban_time = row[6]
          panhash = row[7]
          key_hash = row[8]
          base_id = row[9]
          creator = row[10]
          created = row[11]
        else
          filter = nil
        end

        values = {}
        if (not creator) or (not created)
          creator ||= PandoraGUI.current_user_or_key(true)
          values[:creator] = creator
          values[:created] = time_now
        end
        if (not base_id) or (base_id=='')
          base_id = sbase_id
        end
        if (not key_hash) or (key_hash=='')
          key_hash = skey_panhash
        end
        values[:base_id] = base_id
        values[:key_hash] = key_hash

        values[:addr_from] = host_ip
        values[:addr_from_type] = AT_Ip4
        values[:state]        = state
        values[:sended]       = sended
        values[:received]     = received
        values[:one_ip_count] = one_ip_count+1
        values[:bad_attempts] = bad_attempts
        values[:session_key]  = session_key
        values[:ban_time]     = ban_time
        values[:modified] = time_now

        addr = params['addr']
        if addr and (addr != '')
          host, port, proto = PandoraGUI.decode_node(addr)
          #p log_mes+'ADDR [addr, host, port, proto]='+[addr, host, port, proto].inspect
          if (host and (host != '')) and (port and (port != 0))
            host = host_ip if (not host) or (host=='')
            port = 5577 if (not port) or (port==0)
            values[:domain] = host
            proto ||= ''
            values[:tport] = port if (proto != 'udp')
            values[:uport] = port if (proto != 'tcp')
            values[:addr_type] = AT_Ip4
          end
        end

        if @node_id and (@node_id != 0) and (@node_id != node_id)
          filter2 = {:id=>@node_id}
          @node_id = nil
          sel = node_model.select(filter2, false, 'addr, domain, tport, uport, addr_type', nil, 1)
          if sel and sel.size>0
            addr = sel[0][0]
            domain = sel[0][1]
            tport = sel[0][2]
            uport = sel[0][3]
            addr_type = sel[0][4]
            values[:addr] ||= addr
            values[:domain] ||= domain
            values[:tport] ||= tport
            values[:uport] ||= uport
            values[:addr_type] ||= addr_type
            node_model.update(nil, nil, filter2)
          end
        end

        panhash = node_model.panhash(values)
        values[:panhash] = panhash
        @node_panhash = panhash

        res = node_model.update(values, nil, filter)
      end

      case rcmd
        when EC_Init
          if stage<=ST_Greeting
            if rcode<=ECC_Init_Answer
              if (rcode==ECC_Init_Hello) and ((stage==ST_Protocol) or (stage==ST_Sign))
                recognize_params
                if scmd != EC_Bye
                  vers = params['version']
                  if vers==0
                    addr = params['addr']
                    p log_mes+'addr='+addr.inspect
                    PandoraGUI.check_incoming_addr(addr, host_ip) if addr
                    mode = params['mode']
                    init_skey_or_error(true)
                  else
                    err_scmd('Protocol is not supported ['+vers.to_s+']')
                  end
                end
              elsif ((rcode==ECC_Init_Puzzle) or (rcode==ECC_Init_Phrase)) \
              and ((stage==ST_Protocol) or (stage==ST_Greeting))
                if rdata and (rdata != '')
                  rphrase = rdata
                  params['rphrase'] = rphrase
                else
                  rphrase = params['rphrase']
                end
                p log_mes+'recived phrase len='+rphrase.bytesize.to_s
                if rphrase and (rphrase != '')
                  if rcode==ECC_Init_Puzzle  #phrase for puzzle
                    if ((conn_mode & CM_Hunter) == 0)
                      err_scmd('Puzzle to listener is denied')
                    else
                      delay = rphrase[-2].ord
                      #p 'PUZZLE delay='+delay.to_s
                      start_time = 0
                      end_time = 0
                      start_time = Time.now.to_i if delay
                      suffix = PandoraGUI.find_sha1_solution(rphrase)
                      end_time = Time.now.to_i if delay
                      if delay
                        need_sleep = delay - (end_time - start_time) + 0.5
                        sleep(need_sleep) if need_sleep>0
                      end
                      @sbuf = suffix
                      @scode = ECC_Init_Answer
                    end
                  else #phrase for sign
                    #p log_mes+'SIGN'
                    rphrase = OpenSSL::Digest::SHA384.digest(rphrase)
                    sign = PandoraGUI.make_sign(@rkey, rphrase)
                    len = $base_id.bytesize
                    len = 255 if len>255
                    @sbuf = [len].pack('C')+$base_id[0,len]+sign
                    @scode = ECC_Init_Sign
                    @stage = ST_Exchange if @stage == ST_Greeting
                  end
                  @scmd = EC_Init
                  #@stage = ST_Check
                else
                  err_scmd('Empty received phrase')
                end
              elsif (rcode==ECC_Init_Answer) and (stage==ST_Puzzle)
                interval = nil
                if $puzzle_sec_delay>0
                  start_time = params['puzzle_start']
                  cur_time = Time.now.to_i
                  interval = cur_time - start_time
                end
                if interval and (interval<$puzzle_sec_delay)
                  err_scmd('Too fast puzzle answer')
                else
                  suffix = rdata
                  sphrase = params['sphrase']
                  if PandoraGUI.check_sha1_solution(sphrase, suffix)
                    init_skey_or_error(true)
                  else
                    err_scmd('Wrong sha1 solution')
                  end
                end
              elsif (rcode==ECC_Init_Sign) and (stage==ST_Sign)
                len = rdata[0].ord
                sbase_id = rdata[1, len]
                rsign = rdata[len+1..-1]
                #p log_mes+'recived rsign len='+rsign.bytesize.to_s
                @skey = PandoraGUI.open_key(@skey, @recv_models, true)
                if @skey and @skey[KV_Obj]
                  if PandoraGUI.verify_sign(@skey, OpenSSL::Digest::SHA384.digest(params['sphrase']), rsign)
                    creator = PandoraGUI.current_user_or_key(true)
                    if ((conn_mode & CM_Hunter) != 0) or (not @skey[KV_Creator]) or (@skey[KV_Creator] != creator)
                      # check messages if it's not connection to myself
                      @send_state = (@send_state | CSF_Message)
                    end
                    trust = @skey[KV_Trust]
                    update_node(@skey[KV_Panhash], sbase_id, trust)
                    if ((conn_mode & CM_Hunter) == 0)
                      trust = 0 if (not trust) and $trust_for_captchaed
                    elsif $trust_for_listener and (not (trust.is_a? Float))
                      trust = 0.01
                      @skey[KV_Trust] = trust
                    end
                    p log_mes+'----trust='+trust.inspect
                    if ($captcha_length>0) and (trust.is_a? Integer) and ((conn_mode & CM_Hunter) == 0)
                      @skey[KV_Trust] = 0
                      send_captcha
                    elsif trust.is_a? Float
                      if trust>0.0
                        if (conn_mode & CM_Hunter) == 0
                          @stage = ST_Greeting
                          add_send_segment(EC_Init, true)
                        else
                          @stage = ST_Exchange
                        end
                        @scmd = EC_Data
                        @scode = 0
                        @sbuf = nil
                      else
                        err_scmd('Key is not trusted')
                      end
                    else
                      err_scmd('Key stil is not checked')
                    end
                  else
                    err_scmd('Wrong sign')
                  end
                else
                  err_scmd('Cannot init your key')
                end
              elsif (rcode==ECC_Init_Captcha) and ((stage==ST_Protocol) or (stage==ST_Greeting))
                p log_mes+'CAPTCHA!!!  ' #+params.inspect
                if ((conn_mode & CM_Hunter) == 0)
                  err_scmd('Captcha for listener is denied')
                else
                  clue_length = rdata[0].ord
                  clue_text = rdata[1,clue_length]
                  captcha_buf = rdata[clue_length+1..-1]

                  @entered_captcha = nil
                  if (not $cvpaned.csw)
                    $cvpaned.show_captcha(params['srckey'],
                    @captcha_sw = captcha_buf, clue_text, @node) do |res|
                      @entered_captcha = res
                    end
                    while @entered_captcha.nil?
                      Thread.pass
                    end
                  end

                  if @entered_captcha
                    @scmd = EC_Init
                    @scode = ECC_Init_Answer
                    @sbuf = entered_captcha
                  else
                    err_scmd('Captcha enter canceled')
                  end
                end
              elsif (rcode==ECC_Init_Answer) and (stage==ST_Captcha)
                captcha = rdata
                p log_mes+'recived captcha='+captcha
                if captcha.downcase==params['captcha']
                  @stage = ST_Greeting
                  if not (@skey[KV_Trust].is_a? Float)
                    if $trust_for_captchaed
                      @skey[KV_Trust] = 0.01
                    else
                      @skey[KV_Trust] = nil
                    end
                  end
                  p 'Captcha is GONE!'
                  if (conn_mode & CM_Hunter) == 0
                    add_send_segment(EC_Init, true)
                  end
                  @scmd = EC_Data
                  @scode = 0
                  @sbuf = nil
                else
                  send_captcha
                end
              else
                err_scmd('Wrong stage for rcode')
              end
            else
              err_scmd('Unknown rcode')
            end
          else
            err_scmd('Wrong stage for rcmd')
          end
        when EC_Message, EC_Channel
          #curpage = nil
          p log_mes+'mes len='+@rdata.bytesize.to_s
          if not dialog
            node = PandoraGUI.encode_node(host_ip, port, proto)
            panhash = @skey[KV_Creator]
            @dialog = PandoraGUI.show_talk_dialog(panhash, @node_panhash)
            #curpage = dialog
            Thread.pass
            #sleep(0.1)
            #Thread.pass
            #p log_mes+'NEW dialog1='+dialog.inspect
            #p log_mes+'NEW dialog2='+@dialog.inspect
          end
          if rcmd==EC_Message
            mes = @rdata
            talkview = nil
            #p log_mes+'MES dialog='+dialog.inspect
            talkview = dialog.talkview if dialog
            if talkview
              t = Time.now
              talkview.buffer.insert(talkview.buffer.end_iter, "\n") if talkview.buffer.text != ''
              talkview.buffer.insert(talkview.buffer.end_iter, t.strftime('%H:%M:%S')+' ', 'dude')
              talkview.buffer.insert(talkview.buffer.end_iter, 'Dude:', 'dude_bold')
              talkview.buffer.insert(talkview.buffer.end_iter, ' '+mes)
              talkview.parent.vadjustment.value = talkview.parent.vadjustment.upper
              dialog.update_state(true)
            else
              log_message(LM_Error, 'Пришло сообщение, но лоток чата не найдено!')
            end
          else #EC_Channel
            case rcode
              when ECC_Channel0_Open
                p 'ECC_Channel0_Open'
              when ECC_Channel2_Close
                p 'ECC_Channel2_Close'
            else
              log_message(LM_Error, 'Неизвестный код управления каналом: '+rcode.to_s)
            end
          end
        when EC_Media
          if not dialog
            node = PandoraGUI.encode_node(host_ip, port, proto)
            panhash = @skey[KV_Creator]
            @dialog = PandoraGUI.show_talk_dialog(panhash, @node_panhash)
            dialog.update_state(true)
            Thread.pass
          end
          cannel = rcode
          recv_buf = dialog.recv_media_queue[cannel]
          if not recv_buf
            if cannel==0
              dialog.init_audio_receiver(true, false)
            else
              dialog.init_video_receiver(true, false)
            end
            Thread.pass
            recv_buf = dialog.recv_media_queue[cannel]
          end
          if dialog and recv_buf
            #p 'RECV AUD ('+rdata.size.to_s+')'
            if cannel==0  #audio processes quickly
              buf = Gst::Buffer.new
              buf.data = rdata
              buf.timestamp = Time.now.to_i * Gst::NSECOND
              dialog.appsrcs[cannel].push_buffer(buf)
            else  #video puts to queue
              PandoraGUI.add_block_to_queue(recv_buf, rdata, $media_buf_size)
            end
          end
        when EC_Request
          kind = rcode
          p log_mes+'EC_Request  kind='+kind.to_s
          if (stage==ST_Exchange) or (stage==ST_Greeting) or \
          ((kind==1) and (stage==ST_Sign)) or ((kind==221) and (stage==ST_Protocol))
            panhashes = nil
            if kind==0
              panhashes, len = PandoraKernel.pson_elem_to_rubyobj(panhashes)
            else
              panhashes = [[kind].pack('C')+rdata]
            end
            p log_mes+'panhashes='+panhashes.inspect
            if panhashes.size==1
              panhash = panhashes[0]
              kind = PandoraKernel.kind_from_panhash(panhash)
              p '111111111'
              pson = PandoraGUI.get_record_by_panhash(kind, panhash, false, @recv_models)
              p '222222222'
              if pson
                @scmd = EC_Record
                @scode = kind
                @sbuf = pson
                lang = @sbuf[0].ord
                values = PandoraGUI.pson_to_namehash(@sbuf[1..-1])
                p log_mes+'CHECH PSON !!! [pson, values]='+[pson, values].inspect
              else
                p log_mes+'NO RECORD panhash='+panhash.inspect
                @scmd = EC_More
                @scode = ECC_More_NoRecord
                @sbuf = panhash
              end
            else
              rec_array = []
              panhashes.each do |panhash|
                kind = PandoraKernel.kind_from_panhash(panhash)
                record = PandoraGUI.get_record_by_panhash(kind, panhash, true, @recv_models)
                p log_mes+'EC_Request panhashes='+PandoraKernel.bytes_to_hex(panhash).inspect
                rec_array << record if record
              end
              if rec_array.size>0
                records = PandoraGUI.rubyobj_to_pson_elem(rec_array)
                @scmd = EC_Record
                @scode = 0
                @sbuf = records
              else
                @scmd = EC_More
                @scode = ECC_More_NoRecord
                @sbuf = nil
              end
            end
          else
            err_scmd('Request ('+kind.to_s+') came on wrong stage')
          end
        when EC_Record
          p log_mes+' EC_Record: [rcode, rdata.bytesize]='+[rcode, rdata.bytesize].inspect
          if rcode>0
            kind = rcode
            if (stage==ST_Exchange) or (kind==PK_Key)
              lang = rdata[0].ord
              values = PandoraGUI.pson_to_namehash(rdata[1..-1])
              if not PandoraGUI.save_record(kind, lang, values, @recv_models)
                log_message(LM_Warning, 'Не удалось сохранить запись 1')
              end
              init_skey_or_error(false) if stage<ST_Greeting
            else
              err_scmd('Record ('+kind.to_s+') came on wrong stage')
            end
          else
            if (stage==ST_Exchange)
              records, len = PandoraGUI.pson_elem_to_rubyobj(rdata)
              p log_mes+"!record2! recs="+records.inspect
              records.each do |record|
                kind = record[0].ord
                lang = record[1].ord
                values = PandoraGUI.pson_to_namehash(record[2..-1])
                if not PandoraGUI.save_record(kind, lang, values, @recv_models)
                  log_message(LM_Warning, 'Не удалось сохранить запись 2')
                end
                p 'fields='+fields.inspect
              end
            else
              err_scmd('Records came on wrong stage')
            end
          end
        when EC_Query
          case rcode
            when ECC_Query0_Kinds
              afrom_data=rdata
              @scmd=EC_News
              pkinds="3,7,11"
              @scode=ECC_News0_Kinds
              @sbuf=pkinds
            else #(1..255) - запрос сорта/всех сортов, если 255
              afrom_data=rdata
              akind=rcode
              if akind==ECC_Query255_AllChanges
                pkind=3 #отправка первого кайнда из серии
              else
                pkind=akind  #отправка только запрашиваемого
              end
              @scmd=EC_News
              pnoticecount=3
              @scode=pkind
              @sbuf=[pnoticecount].pack('N')
          end
        when EC_News
          p "news!!!!"
          if rcode==ECC_News0_Kinds
            pcount = rcode
            pkinds = rdata
            @scmd=EC_Query
            @scode=ECC_Query255_AllChanges
            fromdate="01.01.2012"
            @sbuf=fromdate
          else
            p "news more!!!!"
            pkind = rcode
            pnoticecount = rdata.unpack('N')
            @scmd=EC_More
            @scode=0
            @sbuf=''
          end
        when EC_More
          case rcode
            when ECC_More_NoRecord
              p log_mes+'EC_More: No record: panhash='+rdata.inspect
          end
          #case last_scmd
          #  when EC_News
          #    p "!!!!!MORE!"
          #    pkind = 110
          #    if pkind <= 10
          #      @scmd=EC_News
          #      @scode=pkind
          #      ahashid = "id=gfs225,hash=asdsad"
          #      @sbuf=ahashid
          #      pkind += 1
          #    else
          #      @scmd=EC_Bye
          #      @scode=ECC_Bye_Unknown
          #      log_message(LM_Error, '1Получена неизвестная команда от сервера='+rcmd.to_s)
          #      p '1Получена неизвестная команда от сервера='+rcmd.to_s
          #
          #      @conn_state = CS_Stoping
          #    end
          #  else
          #    @scmd=EC_Bye
          #    @scode=ECC_Bye_Unknown
          #    log_message(LM_Error, '2Получена неизвестная команда от сервера='+rcmd.to_s)
          #    p '2Получена неизвестная команда от сервера='+rcmd.to_s
          #    @conn_state = CS_Stoping
          #end
        when EC_News
          p "!!notice!!!"
          pkind = rcode
          phashid = rdata
          @scmd=EC_More
          @scode=0 #0-не надо, 1-патч, 2-запись, 3-миниатюру
          @sbuf=''
        when EC_Patch
          p "!patch!"
        when EC_Pipe
          p "EC_Pipe"
        when EC_Sync
          p log_mes+ "EC_Sync!!!!! SYNC ==== SYNC"
          if rcode==EСC_Sync10_Encode
            @r_encode = true
          end
        when EC_Bye
          if rcode != ECC_Bye_Exit
            mes = rdata
            mes ||= ''
            log_message(LM_Error, _('Error at other side')+' ErrCode='+rcode.to_s+' "'+mes+'"')
          end
          err_scmd(nil, ECC_Bye_Exit, false)
          @conn_state = CS_Stoping
        else
          err_scmd('Unknown command is recieved '+rcmd.to_s, ECC_Bye_Unknown)
          @conn_state = CS_Stoping
      end
      #[rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd]
    end

    # Read next data from socket, or return nil if socket is closed
    # RU: Прочитать следующие данные из сокета, или вернуть nil, если сокет закрылся
    def socket_recv(maxsize)
      recieved = ''
      begin
        #recieved = socket.recv_nonblock(maxsize)
        recieved = socket.recv(maxsize) if (socket and (not socket.closed?))
        recieved = nil if recieved==''  # socket is closed
      rescue
        recieved = ''
      #rescue Errno::EAGAIN       # no data to read
      #  recieved = ''
      #rescue #Errno::ECONNRESET, Errno::EBADF, Errno::ENOTSOCK   # other socket is closed
      #  recieved = nil
      end
      recieved
    end

    # Number of messages per cicle
    # RU: Число сообщений за цикл
    $mes_block_count = 5
    # Number of media blocks per cicle
    # RU: Число медиа блоков за цикл
    $media_block_count = 10
    # Number of requests per cicle
    # RU: Число запросов за цикл
    $inquire_block_count = 1

    # Start two exchange cicle of socket: read and send
    # RU: Запускает два цикла обмена сокета: чтение и отправка
    def start_exchange_cicle(a_send_thread)
      #Thread.critical = true
      #PandoraGUI.add_connection(self)
      #Thread.critical = false

      # Sending thread
      @send_thread = a_send_thread

      @log_mes = 'LIS: '
      if (conn_mode & CM_Hunter)>0
        @log_mes = 'HUN: '
        add_send_segment(EC_Init, true)
      end

      # Read cicle
      # RU: Цикл приёма
      if not read_thread
        @read_thread = Thread.new do
          #read_thread = Thread.current

          sindex = 0
          rindex = 0
          readmode = RM_Comm
          nextreadmode = RM_Comm
          waitlen = CommSize
          rdatasize = 0

          @scmd = EC_More
          @sbuf = ''
          rbuf = AsciiString.new
          @rcmd = EC_More
          @rdata = AsciiString.new
          @last_scmd = scmd

          p log_mes+"Цикл ЧТЕНИЯ начало"
          # Цикл обработки команд и блоков данных
          while (conn_state != CS_Disconnected) and (conn_state != CS_StopRead) \
          and (not socket.closed?) and (recieved = socket_recv(MaxPackSize))
            #p log_mes+"recieved=["+recieved+']  '+socket.closed?.to_s+'  sok='+socket.inspect
            rbuf << AsciiString.new(recieved)
            processedlen = 0
            while (conn_state != CS_Disconnected) and (conn_state != CS_StopRead) \
            and (conn_state != CS_Stoping) and (not socket.closed?) and (rbuf.bytesize>=waitlen)
              #p log_mes+'begin=['+rbuf+']  L='+rbuf.size.to_s+'  WL='+waitlen.to_s
              processedlen = waitlen
              nextreadmode = readmode

              # Определимся с данными по режиму чтения
              case readmode
                when RM_Comm
                  comm = rbuf[0, processedlen]
                  rindex, @rcmd, @rcode, rsegsign, errcode = unpack_comm(comm)
                  if errcode == 0
                    #p log_mes+' RM_Comm: '+[rindex, rcmd, rcode, rsegsign].inspect
                    if rsegsign == Connection::LONG_SEG_SIGN
                      nextreadmode = RM_CommExt
                      waitlen = CommExtSize
                    elsif rsegsign > 0
                      nextreadmode = RM_SegmentS
                      waitlen = rsegsign+4  #+CRC32
                      rdatasize, rsegsize = rsegsign
                    end
                  elsif errcode == 1
                    err_scmd('Wrong CRC of recieved command', ECC_Bye_BadCommCRC)
                  elsif errcode == 2
                    err_scmd('Wrong length of recieved command', ECC_Bye_BadCommLen)
                  else
                    err_scmd('Wrong recieved command', ECC_Bye_Unknown)
                  end
                when RM_CommExt
                  comm = rbuf[0, processedlen]
                  rdatasize, fullcrc32, rsegsize = unpack_comm_ext(comm)
                  #p log_mes+' RM_CommExt: '+[rdatasize, fullcrc32, rsegsize].inspect
                  nextreadmode = RM_Segment1
                  waitlen = rsegsize+4   #+CRC32
                when RM_SegLenN
                  comm = rbuf[0, processedlen]
                  rindex, rsegindex, rsegsize = comm.unpack('CNn')
                  #p log_mes+' RM_SegLenN: '+[rindex, rsegindex, rsegsize].inspect
                  nextreadmode = RM_SegmentN
                  waitlen = rsegsize+4   #+CRC32
                when RM_SegmentS, RM_Segment1, RM_SegmentN
                  #p log_mes+' RM_SegLenX['+readmode.to_s+']  rbuf=['+rbuf+']'
                  if (readmode==RM_Segment1) or (readmode==RM_SegmentN)
                    nextreadmode = RM_SegLenN
                    waitlen = 7    #index + segindex + rseglen (1+4+2)
                  end
                  rsegcrc32 = rbuf[processedlen-4, 4].unpack('N')[0]
                  rseg = AsciiString.new(rbuf[0, processedlen-4])
                  #p log_mes+'rseg=['+rseg+']'
                  fsegcrc32 = Zlib.crc32(rseg)
                  if fsegcrc32 == rsegcrc32
                    @rdata << rseg
                  else
                    err_scmd('Wrong CRC of received segment', ECC_Bye_BadCRC)
                  end
                  #p log_mes+'RM_SegmentX: data['+rdata+']'+rdata.size.to_s+'/'+rdatasize.to_s
                  if rdata.bytesize == rdatasize
                    nextreadmode = RM_Comm
                    waitlen = CommSize
                  elsif rdata.bytesize > rdatasize
                    err_scmd('Too much received data', ECC_Bye_DataTooLong)
                  end
              end
              # Очистим буфер от определившихся данных
              rbuf.slice!(0, processedlen)
              @scmd = EC_Data if (scmd != EC_Bye) and (scmd != EC_Wait)
              # Обработаем поступившие команды и блоки данных
              rdata0 = rdata
              if (scmd != EC_Bye) and (scmd != EC_Wait) and (nextreadmode == RM_Comm)
                #p log_mes+'-->>>> before accept: [rcmd, rcode, rdata.size]='+[rcmd, rcode, rdata.size].inspect
                if @rdata and (@rdata.bytesize>0) and @r_encode
                  #@rdata = PandoraGUI.recrypt(@rkey, @rdata, false, true)
                  #@rdata = Base64.strict_decode64(@rdata)
                  #p log_mes+'::: decode rdata.size='+rdata.size.to_s
                end

                #rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd = \
                  accept_segment #(rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd)

                @rdata = AsciiString.new
                @sbuf ||= AsciiString.new
                #p log_mes+'after accept ==>>>: [scmd, scode, sbuf.size]='+[scmd, scode, @sbuf.size].inspect
                #p log_mes+'accept_request After='+[rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd].inspect
              end

              if scmd != EC_Data
                #@sbuf = '' if scmd == EC_Bye
                #p log_mes+'add to queue [scmd, scode, sbuf]='+[scmd, scode, @sbuf].inspect
                p log_mes+'recv/send: ='+[rcmd, rcode, rdata0.bytesize].inspect+'/'+[scmd, scode, @sbuf].inspect
                #while PandoraGUI.get_queue_state(@send_queue) == QS_Full do
                #  p log_mes+'get_queue_state.MAIN = '+PandoraGUI.get_queue_state(@send_queue).inspect
                #  Thread.pass
                #end
                res = PandoraGUI.add_block_to_queue(@send_queue, [scmd, scode, @sbuf])
                if not res
                  log_message(LM_Error, 'Error while adding segment to queue')
                  conn_state == CS_Stoping
                end
                last_scmd = scmd
                @sbuf = ''
              else
                #p log_mes+'EC_Data(skip): nextreadmode='+nextreadmode.inspect
              end
              readmode = nextreadmode
            end
            if conn_state == CS_Stoping
              @conn_state = CS_StopRead
            end
            Thread.pass
          end
          p log_mes+"Цикл ЧТЕНИЯ конец!"
          #socket.close if not socket.closed?
          #@conn_state = CS_Disconnected
          @read_thread = nil
        end
      end

      #p log_mes+"ФАЗА ОЖИДАНИЯ"

      #while (conn_state != CS_Disconnected) and (stage<ST_Protocoled)
      #  Thread.pass
      #end

      inquirer_step = IS_CreatorCheck

      message_model = PandoraGUI.model_gui('Message', @send_models)

      p log_mes+'ЦИКЛ ОТПРАВКИ начало'
      while (conn_state != CS_Disconnected)
        # отправка сформированных сегментов и их удаление
        if (conn_state != CS_Disconnected)
          send_segment = PandoraGUI.get_block_from_queue(@send_queue)
          while (conn_state != CS_Disconnected) and send_segment
            #p log_mes+' send_segment='+send_segment.inspect
            @scmd, @scode, @sbuf = send_segment
            if @sbuf and (@sbuf.bytesize>0) and @s_encode
              #@sbuf = PandoraGUI.recrypt(@skey, @sbuf, true, false)
              #@sbuf = Base64.strict_encode64(@sbuf)
            end
            @sindex = send_comm_and_data(sindex, @scmd, @scode, @sbuf)
            if (scmd==EC_Sync) and (scode==EСC_Sync10_Encode)
              @s_encode = true
            end
            if (@scmd==EC_Bye)
              p log_mes+'SEND BYE!!!!!!!!!!!!!!!'
              send_segment = nil
              #if not socket.closed?
              #  socket.close_write
              #  socket.close
              #end
              @conn_state = CS_Disconnected
            else
              send_segment = PandoraGUI.get_block_from_queue(@send_queue)
            end
          end
        end

        # выполнить несколько заданий почемучки по его шагам
        processed = 0
        while (conn_state == CS_Connected) and (stage>=ST_Exchange) \
        and ((send_state & (CSF_Message | CSF_Messaging)) == 0) and (processed<$inquire_block_count) \
        and (inquirer_step<IS_Finished)
          case inquirer_step
            when IS_CreatorCheck
              creator = @skey[KV_Creator]
              kind = PandoraKernel.kind_from_panhash(creator)
              res = PandoraGUI.get_record_by_panhash(kind, creator, false, @send_models, false)
              p log_mes+'======  IS_CreatorCheck  creator='+creator.inspect
              if not res
                p log_mes+'======  IS_CreatorCheck  Request!'
                set_request(creator, true)
              end
              inquirer_step += 1
            else
              inquirer_step = IS_Finished
          end
          processed += 1
        end


        # обработка принятых сообщений, их удаление

        # разгрузка принятых буферов в gstreamer
        processed = 0
        cannel = 0
        while (conn_state == CS_Connected) and (stage>=ST_Exchange) \
        and ((send_state & (CSF_Message | CSF_Messaging)) == 0) and (processed<$media_block_count) \
        and dialog and (not dialog.destroyed?) and (cannel<dialog.recv_media_queue.size)
          if dialog.recv_media_pipeline[cannel] and dialog.appsrcs[cannel]
          #and (dialog.recv_media_pipeline[cannel].get_state == Gst::STATE_PLAYING)
            processed += 1
            recv_media_chunk = PandoraGUI.get_block_from_queue(dialog.recv_media_queue[cannel], $media_buf_size)
            if recv_media_chunk and (recv_media_chunk.size>0)
              #p 'GET BUF size='+recv_media_chunk.size.to_s
              buf = Gst::Buffer.new
              buf.data = recv_media_chunk
              buf.timestamp = Time.now.to_i * Gst::NSECOND
              dialog.appsrcs[cannel].push_buffer(buf)
              #recv_media_chunk = PandoraGUI.get_block_from_queue(dialog.recv_media_queue[cannel], $media_buf_size)
            else
              cannel += 1
            end
          else
            cannel += 1
          end
        end

        # обработка принятых запросов, их удаление

        # пакетирование текстовых сообщений
        processed = 0
        #p log_mes+'----------send_state1='+send_state.inspect
        #sleep 1
        if (conn_state == CS_Connected) and (stage>=ST_Exchange) \
        and (((send_state & CSF_Message)>0) or ((send_state & CSF_Messaging)>0))
          @send_state = (send_state & (~CSF_Message))
          if @skey and @skey[KV_Creator]
            filter = {'destination'=>@skey[KV_Creator], 'state'=>0}
            sel = message_model.select(filter, false, 'id, text', 'created', $mes_block_count)
            if sel and (sel.size>0)
              @send_state = (send_state | CSF_Messaging)
              i = 0
              while sel and (i<sel.size) and (processed<$mes_block_count) \
              and (conn_state == CS_Connected)
                processed += 1
                id = sel[i][0]
                text = sel[i][1]
                if add_send_segment(EC_Message, true, text)
                  res = message_model.update({:state=>1}, nil, 'id='+id.to_s)
                  if not res
                    log_message(LM_Error, 'Ошибка обновления сообщения text='+text)
                  end
                else
                  log_message(LM_Error, 'Ошибка отправки сообщения text='+text)
                end
                i += 1
                if (i>=sel.size) and (processed<$mes_block_count) and (conn_state == CS_Connected)
                  #sel = message_model.select('destination="'+node.to_s+'" AND state=0', \
                  #  false, 'id, text', 'created', $mes_block_count)
                  sel = message_model.select(filter, false, 'id, text', 'created', $mes_block_count)
                  if sel and (sel.size>0)
                    i = 0
                  else
                    @send_state = (send_state & (~CSF_Messaging))
                  end
                end
              end
            else
              @send_state = (send_state & (~CSF_Messaging))
            end
          else
            @send_state = (send_state & (~CSF_Messaging))
          end
        end

        # пакетирование медиа буферов
        if ($send_media_queue.size>0) and $send_media_rooms \
        and (conn_state == CS_Connected) and (stage>=ST_Exchange) \
        and ((send_state & CSF_Message) == 0) and dialog and (not dialog.destroyed?) and dialog.room_id \
        and ((dialog.vid_button and (not dialog.vid_button.destroyed?) and dialog.vid_button.active?) \
        or (dialog.snd_button and (not dialog.snd_button.destroyed?) and dialog.snd_button.active?))
          #p 'packbuf '+cannel.to_s
          pointer_ind = PandoraGUI.set_send_ptrind_by_room(dialog.room_id)
          processed = 0
          cannel = 0
          while (conn_state == CS_Connected) \
          and ((send_state & CSF_Message) == 0) and (processed<$media_block_count) \
          and (cannel<$send_media_queue.size) \
          and dialog and (not dialog.destroyed?) \
          and ((dialog.vid_button and (not dialog.vid_button.destroyed?) and dialog.vid_button.active?) \
          or (dialog.snd_button and (not dialog.snd_button.destroyed?) and dialog.snd_button.active?))
            processed += 1
            send_media_chunk = PandoraGUI.get_block_from_queue($send_media_queue[cannel], $media_buf_size, pointer_ind)
            if send_media_chunk
              #p log_mes+'send_media_chunk='+send_media_chunk.size.to_s
              @scmd = EC_Media
              @scode = cannel
              @sbuf = send_media_chunk
              @sindex = send_comm_and_data(sindex, @scmd, @scode, @sbuf)
              if not @sindex
                log_message(LM_Error, 'Ошибка отправки буфера data.size='+send_media_chunk.size.to_s)
              end
            else
              cannel += 1
            end
          end
        end

        if socket.closed?
          @conn_state = CS_Disconnected
        #elsif conn_state == CS_Stoping
        #  add_send_segment(EC_Bye, true)
        end
        Thread.pass
      end

      p log_mes+"Цикл ОТПРАВКИ конец!!!"

      #Thread.critical = true
      PandoraGUI.del_connection(self)
      #Thread.critical = false
      if not socket.closed?
        socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
        socket.flush
        socket.print('\000')
        sleep(0.05)
        socket.close_write
        socket.close
      end
      @conn_state = CS_Disconnected
      @socket = nil
      @send_thread = nil

      if dialog and (not dialog.destroyed?) and (not dialog.online_button.destroyed?)
        dialog.online_button.active = false
      end
    end

  end

  # Check ip is not banned
  # RU: Проверяет, не забанен ли ip
  def self.ip_is_not_banned(host_ip)
    true
  end

  # Take next client socket from listener, or return nil
  # RU: Взять следующий сокет клиента со слушателя, или вернуть nil
  def self.get_listener_client_or_nil(server)
    client = nil
    begin
      client = server.accept_nonblock
    rescue Errno::EAGAIN, Errno::EWOULDBLOCK
      client = nil
    end
    client
  end

  $listen_thread = nil

  def self.correct_lis_btn_state
    tool_btn = $toggle_buttons[SF_Listen]
    tool_btn.good_set_active($listen_thread != nil) if tool_btn
  end

  # Open server socket and begin listen
  # RU: Открывает серверный сокет и начинает слушать
  def self.start_or_stop_listen
    get_exchage_params
    if not $listen_thread
      user = current_user_or_key(true)
      if user
        set_status_field(SF_Listen, 'Listening', nil, true)
        $port = get_param('tcp_port')
        $host = get_param('local_host')
        $listen_thread = Thread.new do
          begin
            addr_str = $host.to_s+':'+$port.to_s
            server = TCPServer.open($host, $port)
            addr_str = server.addr[3].to_s+(':')+server.addr[1].to_s
            log_message(LM_Info, 'Слушаю порт '+addr_str)
          rescue
            server = nil
            log_message(LM_Warning, 'Не могу открыть порт '+addr_str)
          end
          Thread.current[:listen_server_socket] = server
          Thread.current[:need_to_listen] = (server != nil)
          while Thread.current[:need_to_listen] and server and not server.closed?
            # Создать поток при подключении клиента
            client = get_listener_client_or_nil(server)
            while Thread.current[:need_to_listen] and not server.closed? and not client
              sleep 0.03
              #Thread.pass
              #Gtk.main_iteration
              client = get_listener_client_or_nil(server)
            end

            if Thread.current[:need_to_listen] and not server.closed? and client
              Thread.new(client) do |socket|
                log_message(LM_Info, "Подключился клиент: "+socket.peeraddr.inspect)

                #local_address
                host_ip = socket.peeraddr[2]

                if ip_is_not_banned(host_ip)
                  host_name = socket.peeraddr[3]
                  port = socket.peeraddr[1]
                  #port = socket.addr[1] if host_ip==socket.addr[2] # hack for short circuit!!!
                  proto = "tcp"
                  node = encode_node(host_ip, port, proto)
                  p "LISTEN: node: "+node.inspect

                  connection = connection_of_node(node)
                  if connection
                    log_message(LM_Info, "Замкнутая петля: "+socket.to_s)
                    while connection and (connection.conn_state==CS_Connected) and not socket.closed?
                      begin
                        buf = socket.recv(MaxPackSize) if not socket.closed?
                      rescue
                        buf = ''
                      end
                      #socket.write(buf)
                      socket.send(buf, 0) if (not socket.closed? and buf and (buf.bytesize>0))
                      connection = connection_of_node(node)
                    end
                  else
                    conn_state = CS_Connected
                    conn_mode = 0
                    #p "serv: conn_mode: "+ conn_mode.inspect
                    connection = Connection.new(host_name, host_ip, port, proto, node, conn_mode, conn_state)
                    connection.socket = socket
                    #connection.post_init
                    #p "server: connection="+ connection.inspect
                    #p "server: $connections"+ $connections.inspect
                    #p 'LIS_SOCKET: '+socket.methods.inspect
                    connection.start_exchange_cicle(Thread.current)
                    del_connection(connection)
                    p "END LISTEN SOKET CLIENT!!!"
                  end
                else
                  log_message(LM_Info, "IP забанен: "+host_ip.to_s)
                end
                socket.close if not socket.closed?
                log_message(LM_Info, "Отключился клиент: "+socket.to_s)
              end
            end
          end
          server.close if server and not server.closed?
          log_message(LM_Info, 'Слушатель остановлен '+addr_str) if server
          set_status_field(SF_Listen, 'Not listen', nil, false)
          $listen_thread = nil
        end
      else
        correct_lis_btn_state
      end
    else
      p server = $listen_thread[:listen_server_socket]
      $listen_thread[:need_to_listen] = false
      #server.close if not server.closed?
      #$listen_thread.join(2) if $listen_thread
      #$listen_thread.exit if $listen_thread
      correct_lis_btn_state
    end
  end

  # Find or create connection with necessary node
  # RU: Находит или создает соединение с нужным узлом
  def self.find_or_start_connection(node, send_state_add=nil, dialog=nil, node_id=nil)
    send_state_add ||= 0
    connection = connection_of_node(node)
    if connection
      connection.send_state = (connection.send_state | send_state_add)
      connection.dialog ||= dialog
      if connection.dialog and connection.dialog.online_button
        connection.dialog.online_button.active = (connection.socket and (not connection.socket.closed?))
      end
    else
      host, port, proto = decode_node(node)
      connection = Connection.new(host, host, port, proto, node, CM_Hunter, CS_Disconnected, node_id)
      Thread.new(connection) do |connection|
        connection.conn_state  = CS_Connecting
        p 'find1: connection.send_state='+connection.send_state.inspect
        connection.send_state = (connection.send_state | send_state_add)
        p 'find2: connection.send_state='+connection.send_state.inspect
        connection.dialog = dialog
        p "start_or_find_conn: THREAD connection="+ connection.inspect
        #p "start_or_find_conn: THREAD $connections"+ $connections.inspect
        host, port, proto = decode_node(node)
        conn_state = CS_Disconnected
        begin
          socket = TCPSocket.open(host, port)
          conn_state = CS_Connected
          connection.host_ip = socket.addr[2]
        rescue #IO::WaitReadable, Errno::EINTR
          socket = nil
          #p "!!Conn Err!!"
          log_message(LM_Warning, "Не удается подключиться к: "+host+':'+port.to_s)
        end
        connection.socket = socket
        if connection.dialog and connection.dialog.online_button
          connection.dialog.online_button.active = (connection.socket and (not connection.socket.closed?))
        end
        connection.conn_state = conn_state
        if socket
          #connection.post_init
          connection.node = encode_node(connection.host_ip, connection.port, connection.proto)
          #connection.dialog.online_button.active = true if connection.dialog
          #p "start_or_find_conn1: connection="+ connection.inspect
          #p "start_or_find_conn1: $connections"+ $connections.inspect
          # Вызвать активный цикл собработкой данных
          log_message(LM_Info, "Подключился к серверу: "+socket.to_s)
          connection.start_exchange_cicle(Thread.current)
          socket.close if not socket.closed?
          log_message(LM_Info, "Отключился от сервера: "+socket.to_s)
        end
        #connection.socket = nil
        #connection.dialog.online_button.active = false if connection.dialog
        p "END HUNTER CLIENT!!!!"
        #Thread.critical = true
        del_connection(connection)
        #Thread.critical = false
        #connection.send_thread = nil
      end
      #while wait_connection and connection and (connection.conn_state==CS_Connecting)
      #  sleep 0.05
        #Thread.pass
        #Gtk.main_iteration
      #  connection = connection_of_node(node)
      #end
      #p "start_or_find_con: THE end! CONNECTION="+ connection.to_s
      #p "start_or_find_con: THE end! wait_connection="+wait_connection.to_s
      #p "start_or_find_con: THE end! conn_state="+conn_state.to_s
      connection = connection_of_node(node)
    end
    connection
  end

  # Stop connection with a node
  # RU: Останавливает соединение с заданным узлом
  def self.stop_connection(node, wait_disconnect=true)
    p 'stop_connection node='+node.inspect
    connection = connection_of_node(node)
    if connection and (connection.conn_state != CS_Disconnected)
      #p 'stop_connection node='+connection.inspect
      connection.conn_state = CS_Stoping
      while wait_disconnect and connection and (connection.conn_state != CS_Disconnected)
        sleep 0.05
        #Thread.pass
        #Gtk.main_iteration
        connection = connection_of_node(node)
      end
      connection = connection_of_node(node)
    end
    connection and (connection.conn_state != CS_Disconnected) and wait_disconnect
  end

  # Form node marker
  # RU: Сформировать маркер узла
  def self.encode_node(host, port, proto)
    host ||= ''
    port ||= ''
    proto ||= ''
    node = host+'='+port.to_s+proto
  end

  # Unpack node marker
  # RU: Распаковать маркер узла
  def self.decode_node(node)
    i = node.index('=')
    if i
      host = node[0, i]
      port = node[i+1, node.size-4-i].to_i
      proto = node[node.size-3, 3]
    else
      host = node
      port = 5577
      proto = 'tcp'
    end
    [host, port, proto]
  end

  def self.check_incoming_addr(addr, host_ip)
    res = false
    #p 'check_incoming_addr  [addr, host_ip]='+[addr, host_ip].inspect
    if (addr.is_a? String) and (addr.size>0)
      host, port, proto = decode_node(addr)
      host.strip!
      host = host_ip if (not host) or (host=='')
      #p 'check_incoming_addr  [host, port, proto]='+[host, port, proto].inspect
      if (host.is_a? String) and (host.size>0)
        p 'check_incoming_addr DONE [host, port, proto]='+[host, port, proto].inspect
        res = true
      end
    end
  end

  $hunter_thread = nil

  def self.correct_hunt_btn_state
    tool_btn = $toggle_buttons[SF_Hunt]
    tool_btn.good_set_active($hunter_thread != nil) if tool_btn
  end

  # Start hunt
  # RU: Начать охоту
  def self.hunt_nodes(round_count=1)
    if $hunter_thread
      $hunter_thread.exit
      $hunter_thread = nil
      correct_hunt_btn_state
    else
      user = current_user_or_key(true)
      if user
        node_model = PandoraModel::Node.new
        filter = 'addr<>"" OR domain<>""'
        flds = 'id, addr, domain, tport'
        sel = node_model.select(filter, false, flds)
        if sel and sel.size>0
          $hunter_thread = Thread.new(node_model, filter, flds, sel) \
          do |node_model, filter, flds, sel|
            set_status_field(SF_Hunt, 'Hunting', nil, true)
            while round_count>0
              if sel and sel.size>0
                sel.each do |row|
                  node_id = row[0]
                  addr   = row[1]
                  domain = row[2]
                  tport = 0
                  begin
                    tport = row[3].to_i
                  rescue
                  end
                  tport = $port if (not tport) or (tport==0) or (tport=='')
                  domain = addr if ((not domain) or (domain == ''))
                  node = encode_node(domain, tport, 'tcp')
                  connection = find_or_start_connection(node, nil, nil, node_id)
                end
                round_count -= 1
                if round_count>0
                  sleep 3
                  sel = node_model.select(filter, false, flds)
                end
              else
                round_count = 0
              end
            end
            $hunter_thread = nil
            set_status_field(SF_Hunt, 'No hunt', nil, false)
          end
        else
          correct_hunt_btn_state
          dialog = Gtk::MessageDialog.new($window, \
            Gtk::Dialog::MODAL | Gtk::Dialog::DESTROY_WITH_PARENT, \
            Gtk::MessageDialog::INFO, Gtk::MessageDialog::BUTTONS_OK_CANCEL, \
            _('Enter at least one node'))
          dialog.title = _('Note')
          dialog.default_response = Gtk::Dialog::RESPONSE_OK
          dialog.icon = $window.icon
          try = (dialog.run == Gtk::Dialog::RESPONSE_OK)
          if try
            do_menu_act('Node')
          end
          dialog.destroy
        end
      else
        correct_hunt_btn_state
      end
    end
  end

  CSI_Persons = 0
  CSI_Keys    = 1
  CSI_Nodes   = 2

  $key_watch_lim   = 5
  $sign_watch_lim  = 5

  # Get person panhash by any panhash
  # RU: Получить панхэш персоны по произвольному панхэшу
  def self.extract_connset_from_panhash(connset, panhashs)
    persons, keys, nodes = connset
    panhashs = [panhashs] if not panhashs.is_a? Array
    #p '--extract_connset_from_panhash  connset='+connset.inspect
    panhashs.each do |panhash|
      kind = PandoraKernel.kind_from_panhash(panhash)
      panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
      if panobjectclass
        if panobjectclass <= PandoraModel::Person
          persons << panhash
        elsif panobjectclass <= PandoraModel::Node
          nodes << panhash
        else
          if panobjectclass <= PandoraModel::Created
            model = model_gui(panobjectclass.ider)
            filter = {:panhash=>panhash}
            sel = model.select(filter, false, 'creator')
            if sel and sel.size>0
              sel.each do |row|
                persons << row[0]
              end
            end
          end
        end
      end
    end
    #p 'connset2='+connset.inspect
    persons.uniq!
    keys.uniq!
    if nodes.size == 0
      model = model_gui('Key')
      persons.each do |person|
        sel = model.select({:creator=>person}, false, 'panhash', 'modified DESC', $key_watch_lim)
        if sel and (sel.size>0)
          sel.each do |row|
            keys << row[0]
          end
        end
      end
      if keys.size == 0
        model = model_gui('Sign')
        persons.each do |person|
          sel = model.select({:creator=>person}, false, 'key_hash', 'modified DESC', $sign_watch_lim)
          if sel and (sel.size>0)
            sel.each do |row|
              keys << row[0]
            end
          end
        end
      end
      keys.uniq!
      model = model_gui('Node')
      keys.each do |key|
        sel = model.select({:key_hash=>key}, false, 'panhash')
        if sel and (sel.size>0)
          sel.each do |row|
            nodes << row[0]
          end
        end
      end
      #p '[keys, nodes]='+[keys, nodes].inspect
      #p 'connset3='+connset.inspect
    end
    nodes.uniq!
    nodes.size
  end

  # Extend lists of persons, nodes and keys by relations
  # RU: Расширить списки персон, узлов и ключей пройдясь по связям
  def self.extend_connset_by_relations(connset)
    added = 0
    # need to copmose by relations
    added
  end

  # Start a thread which is searching additional nodes and keys
  # RU: Запуск потока, которые ищет дополнительные узлы и ключи
  def self.start_extending_connset_by_hunt(connset)
    started = true
    # heen hunt with poll of nodes
    started
  end

  def self.consctruct_room_id(persons)
    sha1 = Digest::SHA1.new
    persons.each do |panhash|
      sha1.update(panhash)
    end
    res = sha1.digest
  end

  def self.consctruct_room_title(persons)
    res = PandoraKernel.bytes_to_hex(persons[0])[4,16]
  end

  def self.find_active_sender(not_this=nil)
    res = nil
    $notebook.children.each do |child|
      if (child != not_this) and (child.is_a? TalkScrolledWindow) and child.vid_button.active?
        return child
      end
    end
    res
  end

  # Correct bug with dissapear Enter press event
  # RU: Исправляет баг с исчезновением нажатия Enter
  def self.hack_enter_bug(enterbox)
    # because of bug - doesnt work Enter at 'key-press-event'
    enterbox.signal_connect('key-release-event') do |widget, event|
      if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
        widget.signal_emit('key-press-event', event)
        false
      end
    end
  end

  $you_color = 'blue'
  $dude_color = 'red'
  $tab_color = 'blue'
  $read_time = 1.5
  $last_page = nil

  # Talk dialog
  # RU: Диалог разговора
  class TalkScrolledWindow < Gtk::ScrolledWindow
    attr_accessor :room_id, :connset, :online_button, :snd_button, :vid_button, :talkview, \
      :editbox, :area_send, :area_recv, :recv_media_pipeline, :appsrcs, :connection, :ximagesink, \
      :read_thread, :recv_media_queue, :send_display_handler, :recv_display_handler

    include PandoraGUI

    CL_Online = 0
    CL_Name   = 1

    # Show conversation dialog
    # RU: Показать диалог общения
    def initialize(known_node, a_room_id, a_connset, title)
      super(nil, nil)

      @room_id = a_room_id
      @connset = a_connset
      @recv_media_queue = []
      @recv_media_pipeline = []
      @appsrcs = []

      p 'TALK INIT [known_node, a_room_id, a_connset, title]='+[known_node, a_room_id, a_connset, title].inspect

      model = PandoraGUI.model_gui('Node')
      node_list = []
      connset[CSI_Nodes].each do |nodehash|
        sel = model.select({:panhash=>nodehash}, false, 'addr, domain, tport')
        if sel and (sel.size>0)
          sel.each do |row|
            addr   = row[0]
            domain = row[1]
            tport = 0
            begin
              tport = row[2].to_i
            rescue
            end
            tport = $port if (not tport) or (tport==0) or (tport=='')
            domain = addr if ((not domain) or (domain == ''))
            node = PandoraGUI.encode_node(domain, tport, 'tcp')
            node_list << node
          end
        end
      end
      p 'TALK INIT2 node_list='+node_list.inspect
      node_list.uniq!

      set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      #sw.name = title
      #sw.add(treeview)
      border_width = 0;

      image = Gtk::Image.new(Gtk::Stock::MEDIA_PLAY, Gtk::IconSize::MENU)
      image.set_padding(2, 0)

      hpaned = Gtk::HPaned.new
      add_with_viewport(hpaned)

      vpaned1 = Gtk::VPaned.new
      vpaned2 = Gtk::VPaned.new

      @area_recv = Gtk::DrawingArea.new
      area_recv.set_size_request(320, 240)
      area_recv.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.new(0, 0, 0))

      hbox = Gtk::HBox.new

      bbox = Gtk::HBox.new
      bbox.border_width = 5
      bbox.spacing = 5

      @online_button = Gtk::CheckButton.new(_('Online'), true)
      online_button.signal_connect('clicked') do |widget|
        if widget.active?
          node_list.each do |node|
            PandoraGUI.find_or_start_connection(node, 0, self)
          end
        else
          node_list.each do |node|
            PandoraGUI.stop_connection(node, false)
          end
        end
      end
      online_button.active = (known_node != nil)

      bbox.pack_start(online_button, false, false, 0)

      @snd_button = Gtk::CheckButton.new(_('Sound'), true)
      snd_button.signal_connect('clicked') do |widget|
        if widget.active?
          if init_audio_sender(true)
            online_button.active = true
          end
        else
          init_audio_sender(false, true)
          init_audio_sender(false)
        end
      end
      bbox.pack_start(snd_button, false, false, 0)

      @vid_button = Gtk::CheckButton.new(_('Video'), true)
      vid_button.signal_connect('clicked') do |widget|
        if widget.active?
          if init_video_sender(true)
            online_button.active = true
          end
        else
          init_video_sender(false, true)
          init_video_sender(false)
        end
      end

      bbox.pack_start(vid_button, false, false, 0)

      hbox.pack_start(bbox, false, false, 1.0)

      vpaned1.pack1(area_recv, false, true)
      vpaned1.pack2(hbox, false, true)
      vpaned1.set_size_request(350, 270)

      @talkview = Gtk::TextView.new
      talkview.set_size_request(200, 200)
      talkview.wrap_mode = Gtk::TextTag::WRAP_WORD
      #view.cursor_visible = false
      #view.editable = false

      talkview.buffer.create_tag('you', 'foreground' => $you_color)
      talkview.buffer.create_tag('dude', 'foreground' => $dude_color)
      talkview.buffer.create_tag('you_bold', 'foreground' => $you_color, 'weight' => Pango::FontDescription::WEIGHT_BOLD)
      talkview.buffer.create_tag('dude_bold', 'foreground' => $dude_color,  'weight' => Pango::FontDescription::WEIGHT_BOLD)

      @editbox = Gtk::TextView.new
      editbox.wrap_mode = Gtk::TextTag::WRAP_WORD
      editbox.set_size_request(200, 70)

      editbox.grab_focus

      talksw = Gtk::ScrolledWindow.new(nil, nil)
      talksw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      talksw.add(talkview)

      editbox.signal_connect('key-press-event') do |widget, event|
        if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
          if editbox.buffer.text != ''
            mes = editbox.buffer.text
            sended = false
            node_list.each do |node|
              if add_and_send_mes(mes)
                sended = true
              end
            end
            if sended
              t = Time.now
              talkview.buffer.insert(talkview.buffer.end_iter, "\n") if talkview.buffer.text != ''
              talkview.buffer.insert(talkview.buffer.end_iter, t.strftime('%H:%M:%S')+' ', 'you')
              talkview.buffer.insert(talkview.buffer.end_iter, 'You:', 'you_bold')
              talkview.buffer.insert(talkview.buffer.end_iter, ' '+mes)
              talkview.parent.vadjustment.value = talkview.parent.vadjustment.upper
              editbox.buffer.text = ''
            end
          end
          true
        elsif (Gdk::Keyval::GDK_Escape==event.keyval)
          editbox.buffer.text = ''
          false
        else
          false
        end
      end

      PandoraGUI.hack_enter_bug(editbox)

      hpaned2 = Gtk::HPaned.new
      @area_send = Gtk::DrawingArea.new
      area_send.set_size_request(120, 90)
      area_send.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.new(0, 0, 0))
      hpaned2.pack1(area_send, false, true)
      hpaned2.pack2(editbox, true, true)

      list_sw = Gtk::ScrolledWindow.new(nil, nil)
      list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
      list_sw.set_policy(Gtk::POLICY_NEVER, Gtk::POLICY_AUTOMATIC)
      #list_sw.visible = false

      list_store = Gtk::ListStore.new(TrueClass, String)
      node_list.each do |node|
        user_iter = list_store.append
        user_iter[CL_Name] = node.inspect
      end

      # create tree view
      list_tree = Gtk::TreeView.new(list_store)
      list_tree.rules_hint = true
      list_tree.search_column = CL_Name

      # column for fixed toggles
      renderer = Gtk::CellRendererToggle.new
      renderer.signal_connect('toggled') do |cell, path_str|
        path = Gtk::TreePath.new(path_str)
        iter = list_store.get_iter(path)
        fixed = iter[CL_Online]
        p 'fixed='+fixed.inspect
        fixed ^= 1
        iter[CL_Online] = fixed
      end

      tit_image = Gtk::Image.new(Gtk::Stock::CONNECT, Gtk::IconSize::MENU)
      #tit_image.set_padding(2, 0)
      tit_image.show_all

      column = Gtk::TreeViewColumn.new('', renderer, 'active' => CL_Online)

      #title_widget = Gtk::HBox.new
      #title_widget.pack_start(tit_image, false, false, 0)
      #title_label = Gtk::Label.new(_('People'))
      #title_widget.pack_start(title_label, false, false, 0)
      column.widget = tit_image


      # set this column to a fixed sizing (of 50 pixels)
      #column.sizing = Gtk::TreeViewColumn::FIXED
      #column.fixed_width = 50
      list_tree.append_column(column)

      # column for description
      renderer = Gtk::CellRendererText.new

      column = Gtk::TreeViewColumn.new(_('Nodes'), renderer, 'text' => CL_Name)
      column.set_sort_column_id(CL_Name)
      list_tree.append_column(column)

      list_sw.add(list_tree)

      hpaned3 = Gtk::HPaned.new
      hpaned3.pack1(list_sw, true, true)
      hpaned3.pack2(talksw, true, true)
      #motion-notify-event  #leave-notify-event  enter-notify-event
      #hpaned3.signal_connect('notify::position') do |widget, param|
      #  if hpaned3.position <= 1
      #    list_tree.set_size_request(0, -1)
      #    list_sw.set_size_request(0, -1)
      #  end
      #end
      hpaned3.position = 1
      hpaned3.position = 0

      area_send.add_events(Gdk::Event::BUTTON_PRESS_MASK)
      area_send.signal_connect('button-press-event') do |widget, event|
        if hpaned3.position <= 1
          list_sw.width_request = 150 if list_sw.width_request <= 1
          hpaned3.position = list_sw.width_request
        else
          list_sw.width_request = list_sw.allocation.width
          hpaned3.position = 0
        end
      end

      area_send.signal_connect('visibility_notify_event') do |widget, event_visibility|
        case event_visibility.state
          when Gdk::EventVisibility::UNOBSCURED, Gdk::EventVisibility::PARTIAL
            init_video_sender(true, true) if not area_send.destroyed?
          when Gdk::EventVisibility::FULLY_OBSCURED
            init_video_sender(false, true) if not area_send.destroyed?
        end
      end

      area_send.signal_connect('destroy') do |*args|
        init_video_sender(false)
      end

      vpaned2.pack1(hpaned3, true, true)
      vpaned2.pack2(hpaned2, false, true)

      hpaned.pack1(vpaned1, false, true)
      hpaned.pack2(vpaned2, true, true)

      area_recv.signal_connect('visibility_notify_event') do |widget, event_visibility|
        case event_visibility.state
          when Gdk::EventVisibility::UNOBSCURED, Gdk::EventVisibility::PARTIAL
            init_video_receiver(true, true, false) if not area_recv.destroyed?
          when Gdk::EventVisibility::FULLY_OBSCURED
            init_video_receiver(false) if not area_recv.destroyed?
        end
      end

      area_recv.signal_connect('destroy') do |*args|
        init_video_receiver(false, false)
      end

      area_recv.show

      label_box = TabLabelBox.new(image, title, self, false, 0) do
        #init_video_sender(false)
        #init_video_receiver(false, false)
        area_send.destroy if not area_send.destroyed?
        area_recv.destroy if not area_recv.destroyed?

        node_list.each do |node|
          PandoraGUI.stop_connection(node, false)
        end
      end

      page = $notebook.append_page(self, label_box)

      self.signal_connect('delete-event') do |*args|
        #init_video_sender(false)
        #init_video_receiver(false, false)
        area_send.destroy if not area_send.destroyed?
        area_recv.destroy if not area_recv.destroyed?
      end

      show_all
      $notebook.page = $notebook.n_pages-1 if not known_node
      editbox.grab_focus
    end

    # Send message to node
    # RU: Отправляет сообщение на узел
    def add_and_send_mes(text)
      res = false
      creator = PandoraGUI.current_user_or_key(true)
      if creator
        online_button.active = true
        #Thread.pass
        time_now = Time.now.to_i
        state = 0
        connset[CSI_Persons].each do |panhash|
          p 'ADD_MESS panhash='+panhash.inspect
          values = {:destination=>panhash, :text=>text, :state=>state, \
            :creator=>creator, :created=>time_now, :modified=>time_now}
          model = PandoraGUI.model_gui('Message')
          panhash = model.panhash(values)
          values['panhash'] = panhash
          res1 = model.update(values, nil, nil)
          res = (res or res1)
        end
        connection = PandoraGUI.connection_of_dialog(self)
        if connection
          connection.send_state = (connection.send_state | CSF_Message)
        end
      end
      res
    end

    $statusicon = nil

    # Update tab color when received new data
    # RU: Обновляет цвет закладки при получении новых данных
    def update_state(received=true, curpage=nil)
      tab_widget = $notebook.get_tab_label(self)
      if tab_widget
        curpage ||= $notebook.get_nth_page($notebook.page)
        # interrupt reading thread (if exists)
        if $last_page and ($last_page.is_a? TalkScrolledWindow) \
        and $last_page.read_thread and (curpage != $last_page)
          $last_page.read_thread.exit
          $last_page.read_thread = nil
        end
        # set self dialog as unread
        if received
          color = Gdk::Color.parse($tab_color)
          tab_widget.label.modify_fg(Gtk::STATE_NORMAL, color)
          tab_widget.label.modify_fg(Gtk::STATE_ACTIVE, color)
          $statusicon.set_message(_('Message')+' ['+tab_widget.label.text+']')
        end
        # run reading thread
        timer_setted = false
        if (not self.read_thread) and (curpage == self) and $window.visible? #and $window.active?
          color = $window.modifier_style.text(Gtk::STATE_NORMAL)
          curcolor = tab_widget.label.modifier_style.fg(Gtk::STATE_ACTIVE)
          if curcolor and (color != curcolor)
            timer_setted = true
            self.read_thread = Thread.new(color) do |color|
              sleep(0.3)
              if (not curpage.destroyed?) and (not curpage.editbox.destroyed?)
                curpage.editbox.grab_focus
              end
              if $window.visible? #and $window.active?
                read_sec = $read_time-0.3
                if read_sec >= 0
                  sleep(read_sec)
                end
                if $window.visible? #and $window.active?
                  if (not self.destroyed?) and (not tab_widget.destroyed?) \
                  and (not tab_widget.label.destroyed?)
                    tab_widget.label.modify_fg(Gtk::STATE_NORMAL, nil)
                    tab_widget.label.modify_fg(Gtk::STATE_ACTIVE, nil)
                    $statusicon.set_message(nil)
                  end
                end
              end
              self.read_thread = nil
            end
          end
        end
        # set focus to editbox
        if curpage and (curpage.is_a? TalkScrolledWindow) and curpage.editbox
          if not timer_setted
            Thread.new do
              sleep(0.3)
              if (not curpage.destroyed?) and (not curpage.editbox.destroyed?)
                curpage.editbox.grab_focus
              end
            end
          end
          Thread.pass
          curpage.editbox.grab_focus
        end
      end
    end

    def parse_gst_string(text)
      elements = []
      text.strip!
      elem = nil
      link = false
      i = 0
      while i<text.size
        j = 0
        while (i+j<text.size) and (not ([' ', '=', "\\", '!', '/', 10.chr, 13.chr].include? text[i+j, 1]))
          j += 1
        end
        #p [i, j, text[i+j, 1], text[i, j]]
        word = nil
        param = nil
        val = nil
        if i+j<text.size
          sym = text[i+j, 1]
          if ['=', '/'].include? sym
            if sym=='='
              param = text[i, j]
              i += j
            end
            i += 1
            j = 0
            quotes = false
            while (i+j<text.size) and (quotes or (not ([' ', "\\", '!', 10.chr, 13.chr].include? text[i+j, 1])))
              if quotes
                if text[i+j, 1]=='"'
                  quotes = false
                end
              elsif (j==0) and (text[i+j, 1]=='"')
                quotes = true
              end
              j += 1
            end
            sym = text[i+j, 1]
            val = text[i, j].strip
            val = val[1..-2] if val and (val.size>1) and (val[0]=='"') and (val[-1]=='"')
            val.strip!
            param.strip! if param
            if (not param) or (param=='')
              param = 'caps'
              if not elem
                word = 'capsfilter'
                elem = elements.size
                elements[elem] = [word, {}]
              end
            end
            #puts '++  [word, param, val]='+[word, param, val].inspect
          else
            word = text[i, j]
          end
          link = true if sym=='!'
        else
          word = text[i, j]
        end
        #p 'word='+word.inspect
        word.strip! if word
        #p '---[word, param, val]='+[word, param, val].inspect
        if param or val
          elements[elem][1][param] = val if elem and param and val
        elsif word and (word != '')
          elem = elements.size
          elements[elem] = [word, {}]
        end
        if link
          elements[elem][2] = true if elem
          elem = nil
          link = false
        end
        #p '===elements='+elements.inspect
        i += j+1
      end
      elements
    end

    def append_elems_to_pipe(elements, pipeline, prev_elem=nil, prev_pad=nil, name_suff=nil)
      # create elements and add to pipeline
      #p '---- begin add&link elems='+elements.inspect
      elements.each do |elem_desc|
        factory = elem_desc[0]
        params = elem_desc[1]
        if factory and (factory != '')
          i = factory.index('.')
          if not i
            elemname = nil
            elemname = factory+name_suff if name_suff
            elem = Gst::ElementFactory.make(factory, elemname)
            if elem
              elem_desc[3] = elem
              if params.is_a? Hash
                params.each do |k, v|
                  v0 = elem.get_property(k)
                  #puts '[factory, elem, k, v]='+[factory, elem, v0, k, v].inspect
                  #v = v[1,-2] if v and (v.size>1) and (v[0]=='"') and (v[-1]=='"')
                  #puts 'v='+v.inspect
                  if (k=='caps') or (v0.is_a? Gst::Caps)
                    v = Gst::Caps.parse(v)
                  elsif (v0.is_a? Integer) or (v0.is_a? Float)
                    if v.index('.')
                      v = v.to_f
                    else
                      v = v.to_i
                    end
                  elsif (v0.is_a? TrueClass) or (v0.is_a? FalseClass)
                    v = ((v=='true') or (v=='1'))
                  end
                  #puts '[factory, elem, k, v]='+[factory, elem, v0, k, v].inspect
                  elem.set_property(k, v)
                  #p '----'
                  elem_desc[4] = v if k=='name'
                end
              end
              pipeline.add(elem) if pipeline
            else
              p 'Cannot create gstreamer element "'+factory+'"'
            end
          end
        end
      end
      # resolve names
      elements.each do |elem_desc|
        factory = elem_desc[0]
        link = elem_desc[2]
        if factory and (factory != '')
          #p '----'
          #p factory
          i = factory.index('.')
          if i
            name = factory[0,i]
            #p 'name='+name
            if name and (name != '')
              elem_desc = elements.find{ |ed| ed[4]==name }
              elem = elem_desc[3]
              if not elem
                p 'find by name in pipeline!!'
                p elem = pipeline.get_by_name(name)
              end
              elem[3] = elem if elem
              if elem
                pad = factory[i+1, -1]
                elem[5] = pad if pad and (pad != '')
              end
              #p 'elem[3]='+elem[3].inspect
            end
          end
        end
      end
      # link elements
      link1 = false
      elem1 = nil
      pad1  = nil
      if prev_elem
        link1 = true
        elem1 = prev_elem
        pad1  = prev_pad
      end
      elements.each_with_index do |elem_desc|
        link2 = elem_desc[2]
        elem2 = elem_desc[3]
        pad2  = elem_desc[5]
        if link1 and elem1 and elem2
          if pad1 or pad2
            pad1 ||= 'src'
            apad2 = pad2
            apad2 ||= 'sink'
            p 'pad elem1.pad1 >> elem2.pad2 - '+[elem1, pad1, elem2, apad2].inspect
            elem1.get_pad(pad1).link(elem2.get_pad(apad2))
          else
            #p 'elem1 >> elem2 - '+[elem1, elem2].inspect
            elem1 >> elem2
          end
        end
        link1 = link2
        elem1 = elem2
        pad1  = pad2
      end
      #p '===final add&link'
      [elem1, pad1]
    end

    def add_elem_to_pipe(str, pipeline, prev_elem=nil, prev_pad=nil, name_suff=nil)
      elements = parse_gst_string(str)
      elem, pad = append_elems_to_pipe(elements, pipeline, prev_elem, prev_pad, name_suff)
      [elem, pad]
    end

    def link_sink_to_area(sink, area, pipeline=nil)
      def set_xid(area, sink)
        if (not area.destroyed?) and area.window and sink and (sink.class.method_defined? 'set_xwindow_id')
          win_id = nil
          if os_family=='windows'
            win_id = area.window.handle
          else
            win_id = area.window.xid
          end
          sink.set_property('force-aspect-ratio', true)
          sink.set_xwindow_id(win_id)
        end
      end

      res = nil
      if area and (not area.destroyed?)
        if (not area.window) and pipeline
          area.realize
          Gtk.main_iteration
        end
        set_xid(area, sink)
      end
      if pipeline and (not pipeline.destroyed?)
        pipeline.bus.add_watch do |bus, message|
          if (message and message.structure and message.structure.name \
          and (message.structure.name == 'prepare-xwindow-id'))
            Gdk::Threads.synchronize do
              Gdk::Display.default.sync
              asink = message.src
              set_xid(area, asink)
            end
          end
          true
        end

        res = area.signal_connect('expose-event') do |*args|
          set_xid(area, sink)
        end
      end
      res
    end

    def get_video_sender_params(src_param = 'video_src_v4l2', \
      send_caps_param = 'video_send_caps_raw_320x240', send_tee_param = 'video_send_tee_def', \
      view1_param = 'video_view1_xv', can_encoder_param = 'video_can_encoder_vp8', \
      can_sink_param = 'video_can_sink_app')

      # getting from setup (will be feature)
      src         = PandoraGUI.get_param(src_param)
      send_caps   = PandoraGUI.get_param(send_caps_param)
      send_tee    = PandoraGUI.get_param(send_tee_param)
      view1       = PandoraGUI.get_param(view1_param)
      can_encoder = PandoraGUI.get_param(can_encoder_param)
      can_sink    = PandoraGUI.get_param(can_sink_param)

      # default param (temporary)
      #src = 'v4l2src decimate=3'
      #send_caps = 'video/x-raw-rgb,width=320,height=240'
      #send_tee = 'ffmpegcolorspace ! tee name=vidtee'
      #view1 = 'queue ! xvimagesink force-aspect-ratio=true'
      #can_encoder = 'vp8enc max-latency=0.5'
      #can_sink = 'appsink emit-signals=true'

      # extend src and its caps
      send_caps = 'capsfilter caps="'+send_caps+'"'

      [src, send_caps, send_tee, view1, can_encoder, can_sink]
    end

    $send_media_pipelines = {}
    $webcam_xvimagesink   = nil

    def init_video_sender(start=true, just_upd_area=false)
      video_pipeline = $send_media_pipelines['video']
      if not start
        if $webcam_xvimagesink and ($webcam_xvimagesink.get_state == Gst::STATE_PLAYING)
          $webcam_xvimagesink.pause
        end
        if just_upd_area
          if send_display_handler
            area_send.signal_handler_disconnect(send_display_handler)
            @send_display_handler = nil
          end
          tsw = PandoraGUI.find_active_sender(self)
          if $webcam_xvimagesink and (not $webcam_xvimagesink.destroyed?) and tsw \
          and tsw.area_send and tsw.area_send.window
            link_sink_to_area($webcam_xvimagesink, tsw.area_send)
            #$webcam_xvimagesink.xwindow_id = tsw.area_send.window.xid
            #p 'RECONN tsw.title='+PandoraGUI.consctruct_room_title(connset[CSI_Persons]).inspect
          end
          #p '--LEAVE'
          area_send.queue_draw if area_send and (not area_send.destroyed?)
        else
          #$webcam_xvimagesink.xwindow_id = 0
          count = PandoraGUI.nil_send_ptrind_by_room(room_id)
          if video_pipeline and (count==0) and (video_pipeline.get_state != Gst::STATE_NULL)
            video_pipeline.stop
            if send_display_handler
              area_send.signal_handler_disconnect(send_display_handler)
              @send_display_handler = nil
            end
            #p '==STOP!!'
          end
        end
        #Thread.pass
      elsif (not self.destroyed?) and (not vid_button.destroyed?) and vid_button.active? \
      and area_send and (not area_send.destroyed?)
        if not video_pipeline
          begin
            Gst.init
            winos = (os_family == 'windows')
            video_pipeline = Gst::Pipeline.new('spipe_v')
            $send_media_pipelines['video'] = video_pipeline

            ##video_src = 'v4l2src decimate=3'
            ##video_src_caps = 'capsfilter caps="video/x-raw-rgb,width=320,height=240"'
            #video_src_caps = 'capsfilter caps="video/x-raw-yuv,width=320,height=240"'
            #video_src_caps = 'capsfilter caps="video/x-raw-yuv,width=320,height=240" ! videorate drop=10'
            #video_src_caps = 'capsfilter caps="video/x-raw-yuv, framerate=10/1, width=320, height=240"'
            #video_src_caps = 'capsfilter caps="width=320,height=240"'
            ##video_send_tee = 'ffmpegcolorspace ! tee name=vidtee'
            #video_send_tee = 'tee name=tee1'
            ##video_view1 = 'queue ! xvimagesink force-aspect-ratio=true'
            ##video_can_encoder = 'vp8enc max-latency=0.5'
            #video_can_encoder = 'vp8enc speed=2 max-latency=2 quality=5.0 max-keyframe-distance=3 threads=5'
            #video_can_encoder = 'ffmpegcolorspace ! videoscale ! theoraenc quality=16 ! queue'
            #video_can_encoder = 'jpegenc quality=80'
            #video_can_encoder = 'jpegenc'
            #video_can_encoder = 'mimenc'
            #video_can_encoder = 'mpeg2enc'
            #video_can_encoder = 'diracenc'
            #video_can_encoder = 'xvidenc'
            #video_can_encoder = 'ffenc_flashsv'
            #video_can_encoder = 'ffenc_flashsv2'
            #video_can_encoder = 'smokeenc keyframe=8 qmax=40'
            #video_can_encoder = 'theoraenc bitrate=128'
            #video_can_encoder = 'theoraenc ! oggmux'
            #video_can_encoder = videorate ! videoscale ! x264enc bitrate=256 byte-stream=true'
            #video_can_encoder = 'queue ! x264enc bitrate=96'
            #video_can_encoder = 'ffenc_h263'
            #video_can_encoder = 'h264enc'
            ##video_can_sink = 'appsink emit-signals=true'

            src_param = PandoraGUI.get_param('video_src')
            send_caps_param = PandoraGUI.get_param('video_send_caps')
            send_tee_param = 'video_send_tee_def'
            view1_param = PandoraGUI.get_param('video_view1')
            can_encoder_param = PandoraGUI.get_param('video_can_encoder')
            can_sink_param = 'video_can_sink_app'

            video_src, video_send_caps, video_send_tee, video_view1, video_can_encoder, video_can_sink \
              = get_video_sender_params(src_param, send_caps_param, send_tee_param, view1_param, \
                can_encoder_param, can_sink_param)

            if winos
              video_src = PandoraGUI.get_param('video_src_win')
              video_src ||= 'dshowvideosrc'
              video_view1 = PandoraGUI.get_param('video_view1_win')
              video_view1 ||= 'queue ! directdrawsink'
            end

            webcam, pad = add_elem_to_pipe(video_src, video_pipeline)
            capsfilter, pad = add_elem_to_pipe(video_send_caps, video_pipeline, webcam, pad)
            tee, teepad = add_elem_to_pipe(video_send_tee, video_pipeline, capsfilter, pad)
            encoder, pad = add_elem_to_pipe(video_can_encoder, video_pipeline, tee, teepad)
            appsink, pad = add_elem_to_pipe(video_can_sink, video_pipeline, encoder, pad)
            $webcam_xvimagesink, pad = add_elem_to_pipe(video_view1, video_pipeline, tee, teepad)

            $send_media_queue[1] ||= PandoraGUI.init_empty_queue(true)
            appsink.signal_connect('new-buffer') do |appsink|
              buf = appsink.pull_buffer
              if buf
                data = buf.data
                PandoraGUI.add_block_to_queue($send_media_queue[1], data, $media_buf_size)
              end
            end
          rescue => err
            $send_media_pipelines['video'] = nil
            mes = 'Camera init exception'
            log_message(LM_Warning, _(mes))
            puts mes+': '+err.message
            vid_button.active = false
          end
        end

        if video_pipeline
          if $webcam_xvimagesink and area_send #and area_send.window
            #$webcam_xvimagesink.xwindow_id = area_send.window.xid
            link_sink_to_area($webcam_xvimagesink, area_send)
          end
          if not just_upd_area
            video_pipeline.stop if (video_pipeline.get_state != Gst::STATE_NULL)
            if send_display_handler
              area_send.signal_handler_disconnect(send_display_handler)
              @send_display_handler = nil
            end
          end
          if not send_display_handler
            @send_display_handler = link_sink_to_area($webcam_xvimagesink, area_send, video_pipeline)
          end
          if $webcam_xvimagesink and area_send and area_send.window
            #$webcam_xvimagesink.xwindow_id = area_send.window.xid
            link_sink_to_area($webcam_xvimagesink, area_send)
          end
          if just_upd_area
            video_pipeline.play if (video_pipeline.get_state != Gst::STATE_PLAYING)
          else
            ptrind = PandoraGUI.set_send_ptrind_by_room(room_id)
            count = PandoraGUI.nil_send_ptrind_by_room(nil)
            if count>0
              #Gtk.main_iteration
              video_pipeline.play if (video_pipeline.get_state != Gst::STATE_PLAYING)
              #p '==*** PLAY'
            end
          end
          #if $webcam_xvimagesink and ($webcam_xvimagesink.get_state != Gst::STATE_PLAYING) \
          #and (video_pipeline.get_state == Gst::STATE_PLAYING)
          #  $webcam_xvimagesink.play
          #end
        end
      end
      video_pipeline
    end

    def get_video_receiver_params(can_src_param = 'video_can_src_app', \
      can_decoder_param = 'video_can_decoder_vp8', recv_tee_param = 'video_recv_tee_def', \
      view2_param = 'video_view2_x')

      # getting from setup (will be feature)
      can_src     = PandoraGUI.get_param(can_src_param)
      can_decoder = PandoraGUI.get_param(can_decoder_param)
      recv_tee    = PandoraGUI.get_param(recv_tee_param)
      view2       = PandoraGUI.get_param(view2_param)

      # default param (temporary)
      #can_src     = 'appsrc emit-signals=false'
      #can_decoder = 'vp8dec'
      #recv_tee    = 'ffmpegcolorspace ! tee'
      #view2       = 'ximagesink sync=false'

      [can_src, can_decoder, recv_tee, view2]
    end

    def init_video_receiver(start=true, can_play=true, init=true)
      if not start
        if ximagesink and (ximagesink.get_state == Gst::STATE_PLAYING)
          if can_play
            ximagesink.pause
          else
            ximagesink.stop
          end
        end
        if recv_display_handler and (not can_play)
          area_recv.signal_handler_disconnect(recv_display_handler)
          @recv_display_handler = nil
        end
      elsif (not self.destroyed?) and area_recv and (not area_recv.destroyed?)
        if (not recv_media_pipeline[1]) and init
          begin
            Gst.init
            winos = (os_family == 'windows')
            @recv_media_queue[1] ||= PandoraGUI.init_empty_queue
            dialog_id = '_v'+PandoraKernel.bytes_to_hex(room_id[0,4])
            @recv_media_pipeline[1] = Gst::Pipeline.new('rpipe'+dialog_id)
            vidpipe = @recv_media_pipeline[1]

            ##video_can_src = 'appsrc emit-signals=false'
            ##video_can_decoder = 'vp8dec'
            #video_can_decoder = 'xviddec'
            #video_can_decoder = 'ffdec_flashsv'
            #video_can_decoder = 'ffdec_flashsv2'
            #video_can_decoder = 'queue ! theoradec ! videoscale ! capsfilter caps="video/x-raw,width=320"'
            #video_can_decoder = 'jpegdec'
            #video_can_decoder = 'schrodec'
            #video_can_decoder = 'smokedec'
            #video_can_decoder = 'oggdemux ! theoradec'
            #video_can_decoder = 'theoradec'
            #! video/x-h264,width=176,height=144,framerate=25/1 ! ffdec_h264 ! videorate
            #video_can_decoder = 'x264dec'
            #video_can_decoder = 'mpeg2dec'
            #video_can_decoder = 'mimdec'
            ##video_recv_tee = 'ffmpegcolorspace ! tee'
            #video_recv_tee = 'tee'
            ##video_view2 = 'ximagesink sync=false'
            #video_view2 = 'queue ! xvimagesink force-aspect-ratio=true sync=false'

            can_src_param = 'video_can_src_app'
            can_decoder_param = PandoraGUI.get_param('video_can_decoder')
            recv_tee_param = 'video_recv_tee_def'
            view2_param = PandoraGUI.get_param('video_view2')

            video_can_src, video_can_decoder, video_recv_tee, video_view2 \
              = get_video_receiver_params(can_src_param, can_decoder_param, \
                recv_tee_param, view2_param)

            if winos
              video_view2 = PandoraGUI.get_param('video_view2_win')
              video_view2 ||= 'queue ! directdrawsink'
            end

            @appsrcs[1], pad = add_elem_to_pipe(video_can_src, vidpipe, nil, nil, dialog_id)
            decoder, pad = add_elem_to_pipe(video_can_decoder, vidpipe, appsrcs[1], pad, dialog_id)
            recv_tee, pad = add_elem_to_pipe(video_recv_tee, vidpipe, decoder, pad, dialog_id)
            @ximagesink, pad = add_elem_to_pipe(video_view2, vidpipe, recv_tee, pad, dialog_id)
          rescue => err
            @recv_media_pipeline[1] = nil
            mes = 'Video receiver init exception'
            log_message(LM_Warning, _(mes))
            puts mes+': '+err.message
            vid_button.active = false
          end
        end
        if recv_media_pipeline[1] and can_play
          if not recv_display_handler and @ximagesink
            @recv_display_handler = link_sink_to_area(@ximagesink, area_recv,  recv_media_pipeline[1])
          end
          recv_media_pipeline[1].play if (recv_media_pipeline[1].get_state != Gst::STATE_PLAYING)
          ximagesink.play if (ximagesink.get_state != Gst::STATE_PLAYING)
        end
      end
    end

    def get_audio_sender_params(src_param = 'audio_src_alsa', \
      send_caps_param = 'audio_send_caps_8000', send_tee_param = 'audio_send_tee_def', \
      can_encoder_param = 'audio_can_encoder_vorbis', can_sink_param = 'audio_can_sink_app')

      # getting from setup (will be feature)
      src = PandoraGUI.get_param(src_param)
      send_caps = PandoraGUI.get_param(send_caps_param)
      send_tee = PandoraGUI.get_param(send_tee_param)
      can_encoder = PandoraGUI.get_param(can_encoder_param)
      can_sink = PandoraGUI.get_param(can_sink_param)

      # default param (temporary)
      #src = 'alsasrc device=hw:0'
      #send_caps = 'audio/x-raw-int,rate=8000,channels=1,depth=8,width=8'
      #send_tee = 'audioconvert ! tee name=audtee'
      #can_encoder = 'vorbisenc quality=0.0'
      #can_sink = 'appsink emit-signals=true'

      # extend src and its caps
      src = src + ' ! audioconvert ! audioresample'
      send_caps = 'capsfilter caps="'+send_caps+'"'

      [src, send_caps, send_tee, can_encoder, can_sink]
    end

    def init_audio_sender(start=true, just_upd_area=false)
      audio_pipeline = $send_media_pipelines['audio']
      #p 'init_audio_sender pipe='+audio_pipeline.inspect+'  btn='+snd_button.active?.inspect
      if not start
        #count = PandoraGUI.nil_send_ptrind_by_room(room_id)
        #if audio_pipeline and (count==0) and (audio_pipeline.get_state != Gst::STATE_NULL)
        if audio_pipeline and (audio_pipeline.get_state != Gst::STATE_NULL)
          audio_pipeline.stop
        end
      elsif (not self.destroyed?) and (not snd_button.destroyed?) and snd_button.active?
        if not audio_pipeline
          begin
            Gst.init
            winos = (os_family == 'windows')
            audio_pipeline = Gst::Pipeline.new('spipe_a')
            $send_media_pipelines['audio'] = audio_pipeline

            ##audio_src = 'alsasrc device=hw:0 ! audioconvert ! audioresample'
            #audio_src = 'autoaudiosrc'
            #audio_src = 'alsasrc'
            #audio_src = 'audiotestsrc'
            #audio_src = 'pulsesrc'
            ##audio_src_caps = 'capsfilter caps="audio/x-raw-int,rate=8000,channels=1,depth=8,width=8"'
            #audio_src_caps = 'queue ! capsfilter caps="audio/x-raw-int,rate=8000,depth=8"'
            #audio_src_caps = 'capsfilter caps="audio/x-raw-int,rate=8000,depth=8"'
            #audio_src_caps = 'capsfilter caps="audio/x-raw-int,endianness=1234,signed=true,width=16,depth=16,rate=22000,channels=1"'
            #audio_src_caps = 'queue'
            ##audio_send_tee = 'audioconvert ! tee name=audtee'
            #audio_can_encoder = 'vorbisenc'
            ##audio_can_encoder = 'vorbisenc quality=0.0'
            #audio_can_encoder = 'vorbisenc quality=0.0 bitrate=16000 managed=true' #8192
            #audio_can_encoder = 'vorbisenc quality=0.0 max-bitrate=32768' #32768  16384  65536
            #audio_can_encoder = 'mulawenc'
            #audio_can_encoder = 'lamemp3enc bitrate=8 encoding-engine-quality=speed fast-vbr=true'
            #audio_can_encoder = 'lamemp3enc bitrate=8 target=bitrate mono=true cbr=true'
            #audio_can_encoder = 'speexenc'
            #audio_can_encoder = 'voaacenc'
            #audio_can_encoder = 'faac'
            #audio_can_encoder = 'a52enc'
            #audio_can_encoder = 'voamrwbenc'
            #audio_can_encoder = 'adpcmenc'
            #audio_can_encoder = 'amrnbenc'
            #audio_can_encoder = 'flacenc'
            #audio_can_encoder = 'ffenc_nellymoser'
            #audio_can_encoder = 'speexenc vad=true vbr=true'
            #audio_can_encoder = 'speexenc vbr=1 dtx=1 nframes=4'
            #audio_can_encoder = 'opusenc'
            ##audio_can_sink = 'appsink emit-signals=true'

            src_param = PandoraGUI.get_param('audio_src')
            send_caps_param = PandoraGUI.get_param('audio_send_caps')
            send_tee_param = 'audio_send_tee_def'
            can_encoder_param = PandoraGUI.get_param('audio_can_encoder')
            can_sink_param = 'audio_can_sink_app'

            audio_src, audio_send_caps, audio_send_tee, audio_can_encoder, audio_can_sink  \
              = get_audio_sender_params(src_param, send_caps_param, send_tee_param, \
                can_encoder_param, can_sink_param)

            if winos
              audio_src = PandoraGUI.get_param('audio_src_win')
              audio_src ||= 'dshowaudiosrc'
            end

            micro, pad = add_elem_to_pipe(audio_src, audio_pipeline)
            capsfilter, pad = add_elem_to_pipe(audio_send_caps, audio_pipeline, micro, pad)
            tee, teepad = add_elem_to_pipe(audio_send_tee, audio_pipeline, capsfilter, pad)
            audenc, pad = add_elem_to_pipe(audio_can_encoder, audio_pipeline, tee, teepad)
            appsink, pad = add_elem_to_pipe(audio_can_sink, audio_pipeline, audenc, pad)

            $send_media_queue[0] ||= PandoraGUI.init_empty_queue(true)
            appsink.signal_connect('new-buffer') do |appsink|
              buf = appsink.pull_buffer
              if buf
                #p 'GET AUDIO ['+buf.size.to_s+']'
                data = buf.data
                PandoraGUI.add_block_to_queue($send_media_queue[0], data, $media_buf_size)
              end
            end
          rescue => err
            $send_media_pipelines['audio'] = nil
            mes = 'Microphone init exception'
            log_message(LM_Warning, _(mes))
            puts mes+': '+err.message
            snd_button.active = false
          end
        end

        if audio_pipeline
          ptrind = PandoraGUI.set_send_ptrind_by_room(room_id)
          count = PandoraGUI.nil_send_ptrind_by_room(nil)
          #p 'AAAAAAAAAAAAAAAAAAA count='+count.to_s
          if (count>0) and (audio_pipeline.get_state != Gst::STATE_PLAYING)
          #if (audio_pipeline.get_state != Gst::STATE_PLAYING)
            audio_pipeline.play
          end
        end
      end
      audio_pipeline
    end

    def get_audio_receiver_params(can_src_param = 'audio_can_src_app', \
      can_decoder_param = 'audio_can_decoder_vorbis', recv_tee_param = 'audio_recv_tee_def', \
      phones_param = 'audio_phones_auto')

      # getting from setup (will be feature)
      can_src     = PandoraGUI.get_param(can_src_param)
      can_decoder = PandoraGUI.get_param(can_decoder_param)
      recv_tee    = PandoraGUI.get_param(recv_tee_param)
      phones      = PandoraGUI.get_param(phones_param)

      # default param (temporary)
      #can_src = 'appsrc emit-signals=false'
      #can_decoder = 'vorbisdec'
      #recv_tee = 'audioconvert ! tee'
      #phones = 'autoaudiosink'

      [can_src, can_decoder, recv_tee, phones]
    end

    def init_audio_receiver(start=true, can_play=true, init=true)
      if not start
        if recv_media_pipeline[0] and (recv_media_pipeline[0].get_state != Gst::STATE_NULL)
          recv_media_pipeline[0].stop
        end
        p 'init_audio_receiver stop ???'
      elsif (not self.destroyed?)
        if (not recv_media_pipeline[0]) #and init
          begin
            Gst.init
            winos = (os_family == 'windows')
            @recv_media_queue[0] ||= PandoraGUI.init_empty_queue
            dialog_id = '_a'+PandoraKernel.bytes_to_hex(room_id[0,4])
            @recv_media_pipeline[0] = Gst::Pipeline.new('rpipe'+dialog_id)
            audpipe = @recv_media_pipeline[0]

            ##audio_can_src = 'appsrc emit-signals=false'
            #audio_can_src = 'appsrc'
            ##audio_can_decoder = 'vorbisdec'
            #audio_can_decoder = 'mulawdec'
            #audio_can_decoder = 'speexdec'
            #audio_can_decoder = 'decodebin'
            #audio_can_decoder = 'decodebin2'
            #audio_can_decoder = 'flump3dec'
            #audio_can_decoder = 'amrwbdec'
            #audio_can_decoder = 'adpcmdec'
            #audio_can_decoder = 'amrnbdec'
            #audio_can_decoder = 'voaacdec'
            #audio_can_decoder = 'faad'
            #audio_can_decoder = 'ffdec_nellymoser'
            #audio_can_decoder = 'flacdec'
            ##audio_recv_tee = 'audioconvert ! tee'
            #audio_phones = 'alsasink'
            ##audio_phones = 'autoaudiosink'
            #audio_phones = 'pulsesink'

            can_src_param = 'audio_can_src_app'
            can_decoder_param = PandoraGUI.get_param('audio_can_decoder')
            recv_tee_param = 'audio_recv_tee_def'
            phones_param = PandoraGUI.get_param('audio_phones')

            audio_can_src, audio_can_decoder, audio_recv_tee, audio_phones \
              = get_audio_receiver_params(can_src_param, can_decoder_param, recv_tee_param, phones_param)

            if winos
              audio_phones = PandoraGUI.get_param('audio_phones_win')
              audio_phones ||= 'autoaudiosink'
            end

            @appsrcs[0], pad = add_elem_to_pipe(audio_can_src, audpipe, nil, nil, dialog_id)
            auddec, pad = add_elem_to_pipe(audio_can_decoder, audpipe, appsrcs[0], pad, dialog_id)
            recv_tee, pad = add_elem_to_pipe(audio_recv_tee, audpipe, auddec, pad, dialog_id)
            audiosink, pad = add_elem_to_pipe(audio_phones, audpipe, recv_tee, pad, dialog_id)
          rescue => err
            @recv_media_pipeline[0] = nil
            mes = 'Audio receiver init exception'
            log_message(LM_Warning, _(mes))
            puts mes+': '+err.message
            snd_button.active = false
          end
        end
        if recv_media_pipeline[0] #and can_play
          recv_media_pipeline[0].play if (recv_media_pipeline[0].get_state != Gst::STATE_PLAYING)
        end
      end
    end

  end

  # Show conversation dialog
  # RU: Показать диалог общения
  def self.show_talk_dialog(panhashes, known_node=nil)
    p 'show_talk_dialog: [panhashes, known_node]='+[panhashes, known_node].inspect
    connset = [[], [], []]
    persons, keys, nodes = connset
    if known_node
      #persons |= panhashes
      persons << panhashes
      nodes << known_node
    else
      extract_connset_from_panhash(connset, panhashes)
    end
    if nodes.size==0
      extend_connset_by_relations(connset)
    end
    if nodes.size==0
      start_extending_connset_by_hunt(connset)
    end
    connset.each do |list|
      list.sort!
    end
    persons.uniq!
    keys.uniq!
    nodes.uniq!
    p 'connset='+connset.inspect

    room_id = consctruct_room_id(persons)
    if known_node
      creator = current_user_or_key(true)
      if (persons.size==1) and (persons[0]==creator)
        room_id << '!'
      end
    end
    p 'room_id='+room_id.inspect
    $notebook.children.each do |child|
      if (child.is_a? TalkScrolledWindow) and (child.room_id==room_id)
        $notebook.page = $notebook.children.index(child) if not known_node
        child.room_id = room_id
        child.connset = connset
        child.online_button.active = (known_node != nil)
        return child
      end
    end

    title = consctruct_room_title(connset[CSI_Persons])
    sw = TalkScrolledWindow.new(known_node, room_id, connset, title)
    sw
  end

  class PandoraStatusIcon < Gtk::StatusIcon
    attr_accessor :main_icon

    def initialize
      super

      @main_icon = nil
      if $window.icon
        @main_icon = $window.icon
      else
        @main_icon = $window.render_icon(Gtk::Stock::HOME, Gtk::IconSize::LARGE_TOOLBAR)
      end

      begin
        @message_icon = Gdk::Pixbuf.new(File.join($pandora_view_dir, 'message.ico'))
      rescue Exception
      end
      if not @message_icon
        @message_icon = $window.render_icon(Gtk::Stock::MEDIA_PLAY, Gtk::IconSize::LARGE_TOOLBAR)
      end

      @message = nil
      @flash_on_mes = false
      @update_main_icon = false
      @flash = false
      @flash_status = 0
      update_icon

      title = $window.title
      tooltip = $window.title

      #set_blinking(true)
      signal_connect('activate') do
        icon_activated
      end

      signal_connect('popup-menu') do |widget, button, activate_time|
        p 'widget, button, activate_time='+[widget, button, activate_time].inspect
        menu = Gtk::Menu.new
        checkmenuitem = Gtk::CheckMenuItem.new('Blink')
        checkmenuitem.signal_connect('activate') do |w|
          if @message
            set_message
          else
            set_message('Иван Петров, сообщение')
          end
        end
        menu.append(checkmenuitem)

        menuitem = Gtk::MenuItem.new(_('_Quit'))
        menuitem.signal_connect("activate") do
          widget.set_visible(false)
          Gtk.main_quit
        end
        menu.append(menuitem)
        menu.show_all
        menu.popup(nil, nil, button, activate_time)
      end
    end

    def set_message(message=nil)
      if (message.is_a? String) and (message.size>0)
        @message = message
        set_tooltip(message)
        set_flash(true) if @flash_on_mes
      else
        @message = nil
        set_tooltip($window.title)
        set_flash(false)
      end
      update_icon
    end

    def set_flash(flash=true)
      @flash = flash
      if flash and (not @timer)
        @flash_status = 1
        update_icon
        timeout_func
      end
    end

    def update_icon
      if @message and ((not @flash) or (@flash_status==1))
        self.pixbuf = @message_icon
      else
        self.pixbuf = @main_icon
      end
      $window.icon = self.pixbuf if (@update_main_icon and $window.visible?)
    end

    def timeout_func
      @timer = GLib::Timeout.add(800) do
        next_step = true
        if @flash_status == 0
          @flash_status = 1
        else
          @flash_status = 0
          next_step = false if not @flash
        end
        update_icon
        @timer = nil if not next_step
        next_step
      end
    end

    def icon_activated
      #$window.skip_taskbar_hint = false
      if $window.visible?
        if $window.active?
          $window.hide
        else
          $window.present
        end
      else
        $window.deiconify
        $window.show_all
        #$statusicon.visible = false
        $window.present
        update_icon if @update_main_icon
        if @message
          page = $notebook.page
          if (page >= 0)
            cur_page = $notebook.get_nth_page(page)
            if cur_page.is_a? PandoraGUI::TalkScrolledWindow
              cur_page.update_state(false, cur_page)
            end
          else
            set_message(nil) if ($notebook.n_pages == 0)
          end
        end
      end
    end

  end

  # Menu event handler
  # RU: Обработчик события меню
  def self.do_menu_act(command)
    widget = nil
    if not command.is_a? String
      widget = command
      command = widget.name
    end
    case command
      when 'Quit'
        $window.destroy
      when 'About'
        show_about
      when 'Close'
        if $notebook.page >= 0
          page = $notebook.get_nth_page($notebook.page)
          tab = $notebook.get_tab_label(page)
          close_btn = tab.children[tab.children.size-1].children[0]
          close_btn.clicked
        end
      when 'Create','Edit','Delete','Copy', 'Dialog'
        if $notebook.page >= 0
          sw = $notebook.get_nth_page($notebook.page)
          treeview = sw.children[0]
          act_panobject(treeview, command) if treeview.is_a? PandoraGUI::SubjTreeView
        end
      when 'Clone'
        if $notebook.page >= 0
          sw = $notebook.get_nth_page($notebook.page)
          treeview = sw.children[0]
          panobject = treeview.panobject
          panobject.update(nil, nil, nil)
          panobject.class.tab_fields(true)
        end
      when 'Listen'
        start_or_stop_listen
      #when 'Connect'
      #  if $notebook.page >= 0
      #    sw = $notebook.get_nth_page($notebook.page)
      #    treeview = sw.children[0]
      #    show_talk_dialog(panhash0)
      #    node = define_node_by_current_record(treeview)
      #    find_or_start_connection(node)
      #  end
      when 'Hunt'
        hunt_nodes
      when 'Authorize'
        key = current_key(true)
        #p '=====curr_key:'+key.inspect
=begin
        if key

        ##PandoraKernel.save_as_language($lang)
        #keys = generate_key('RSA', 2048)
        ##keys[1] = nil
        #keys[2] = 'RSA'
        #keys[3] = '12345'
        #p '=====generate_key:'+keys.inspect
        #key = init_key(keys)
          data = 'Test string!'
          sign = make_sign(key, data)
          p '=====make_sign:'+sign.inspect
          p 'verify_sign='+verify_sign(key, data, sign).inspect
        #p 'verify_sign2='+verify_sign(key, data+'aa', sign).inspect

        #encrypted = encrypt(key.public_key, data)
        #p '=====encrypted:'+encrypted.inspect
        #decrypted = decrypt(key, encrypted)
        #p '=====decrypted:'+decrypted.inspect
        end
=end
      when 'Wizard'

        #p pson = rubyobj_to_pson_elem(Time.now)
        #p elem = pson_elem_to_rubyobj(pson)
        #p pson = rubyobj_to_pson_elem(12345)
        #p elem = pson_elem_to_rubyobj(pson)
        #p pson = rubyobj_to_pson_elem(['aaa','bbb'])
        #p elem = pson_elem_to_rubyobj(pson)
        #p pson = rubyobj_to_pson_elem({'zzz'=>'bcd', 'ann'=>['789',123], :bbb=>'dsd'})
        #p elem = pson_elem_to_rubyobj(pson)

        p OpenSSL::Cipher::ciphers

        cipher_hash = encode_cipher_and_hash(KT_Bf, KH_Sha2 | KL_bit256)
        #cipher_hash = encode_cipher_and_hash(KT_Aes | KL_bit256, KH_Sha2 | KL_bit256)
        p 'cipher_hash16='+cipher_hash.to_s(16)
        type_klen = KT_Rsa | KL_bit2048
        cipher_key = '123'
        p keys = generate_key(type_klen, cipher_hash, cipher_key)

        #typ, count = encode_pson_type(PT_Str, 0x1FF)
        #p decode_pson_type(typ)

        #p pson = namehash_to_pson({:first_name=>'Ivan', :last_name=>'Inavov', 'ddd'=>555})
        #p hash = pson_to_namehash(pson)

        #p get_param('base_id')
      when 'Profile'
        p '1cc'
        $cvpaned.show_captcha('abc123', $window.icon.save_to_buffer('jpeg')) do |text|
          p 'cap_text='+text.inspect
        end
        p '2cc'
      else
        panobj_id = command
        if PandoraModel.const_defined? panobj_id
          panobject_class = PandoraModel.const_get(panobj_id)
          show_panobject_list(panobject_class, widget)
        else
          log_message(LM_Warning, _('Menu handler is not defined yet')+' "'+panobj_id+'"')
        end
    end
  end

  # Menu structure
  # RU: Структура меню
  def self.menu_items
    [
    [nil, nil, '_World'],
    ['Person', Gtk::Stock::ORIENTATION_PORTRAIT, 'People'],
    ['Community', nil, 'Communities'],
    ['-', nil, '-'],
    ['Article', Gtk::Stock::DND, 'Articles'],
    ['Blob', Gtk::Stock::HARDDISK, 'Files'], #Gtk::Stock::FILE
    ['-', nil, '-'],
    ['Country', nil, 'States'],
    ['City', nil, 'Towns'],
    ['Street', nil, 'Streets'],
    ['Thing', nil, 'Things'],
    ['Activity', nil, 'Activities'],
    ['Word', Gtk::Stock::SPELL_CHECK, 'Words'],
    ['Language', nil, 'Languages'],
    ['Address', nil, 'Addresses'],
    ['Contact', nil, 'Contacts'],
    ['Document', nil, 'Documents'],
    ['-', nil, '-'],
    ['Relation', nil, 'Relations'],
    ['Opinion', nil, 'Opinions'],
    [nil, nil, '_Bussiness'],
    ['Partner', nil, 'Partners'],
    ['Company', nil, 'Companies'],
    ['-', nil, '-'],
    ['Ad', nil, 'Ads'],
    ['Order', nil, 'Orders'],
    ['Deal', nil, 'Deals'],
    ['Waybill', nil, 'Waybills'],
    ['Debt', nil, 'Debts'],
    ['Guaranty', nil, 'Guaranties'],
    ['-', nil, '-'],
    ['Storage', nil, 'Storages'],
    ['Product', nil, 'Products'],
    ['Service', nil, 'Services'],
    ['Currency', nil, 'Currency'],
    ['Contract', nil, 'Contracts'],
    ['Report', nil, 'Reports'],
    [nil, nil, '_Region'],
    ['Citizen', nil, 'Citizens'],
    ['Union', nil, 'Unions'],
    ['-', nil, '-'],
    ['Project', nil, 'Projects'],
    ['Resolution', nil, 'Resolutions'],
    ['Law', nil, 'Laws'],
    ['-', nil, '-'],
    ['Contribution', nil, 'Contributions'],
    ['Expenditure', nil, 'Expenditures'],
    ['-', nil, '-'],
    ['Offense', nil, 'Offenses'],
    ['Punishment', nil, 'Punishments'],
    ['-', nil, '-'],
    ['Resource', nil, 'Resources'],
    ['Delegation', nil, 'Delegations'],
    [nil, nil, '_Pandora'],
    ['Parameter', Gtk::Stock::PREFERENCES, 'Parameters'],
    ['-', nil, '-'],
    ['Key', Gtk::Stock::DIALOG_AUTHENTICATION, 'Keys'],
    ['Sign', nil, 'Signs'],
    ['Node', Gtk::Stock::NETWORK, 'Nodes'],
    ['Message', nil, 'Messages'],
    ['Patch', nil, 'Patches'],
    ['Event', nil, 'Events'],
    ['Fishhook', nil, 'Fishhooks'],
    ['-', nil, '-'],
    ['Authorize', nil, 'Authorize', '<control>I'],
    ['Listen', Gtk::Stock::CONNECT, 'Listen', '<control>L', :check],
    ['Hunt', Gtk::Stock::REFRESH, 'Hunt', '<control>H', :check],
    ['Search', Gtk::Stock::FIND, 'Search'],
    ['-', nil, '-'],
    ['Profile', Gtk::Stock::HOME, 'Profile'],
    ['Wizard', Gtk::Stock::PROPERTIES, 'Wizards'],
    ['-', nil, '-'],
    ['Quit', Gtk::Stock::QUIT, '_Quit', '<control>Q'],
    ['Close', Gtk::Stock::CLOSE, '_Close', '<control>W'],
    ['-', nil, '-'],
    ['About', Gtk::Stock::ABOUT, '_About']
    ]
  end

  # Creating menu item from its description
  # RU: Создание пункта меню по его описанию
  def self.create_menu_item(mi)
    menuitem = nil
    if mi[0] == '-'
      menuitem = Gtk::SeparatorMenuItem.new
    else
      text = _(mi[2])
      #if (mi[4] == :check)
      #  menuitem = Gtk::CheckMenuItem.new(mi[2])
      #  label = menuitem.children[0]
      #  #label.set_text(mi[2], true)
      if mi[1]
        menuitem = Gtk::ImageMenuItem.new(mi[1])
        label = menuitem.children[0]
        label.set_text(text, true)
      else
        menuitem = Gtk::MenuItem.new(text)
      end
      if mi[3]
        key, mod = Gtk::Accelerator.parse(mi[3])
        menuitem.add_accelerator('activate', $group, key, mod, Gtk::ACCEL_VISIBLE)
      end
      menuitem.name = mi[0]
      menuitem.signal_connect('activate') { |widget| do_menu_act(widget) }
    end
    menuitem
  end

  def self.fill_menubar(menubar)
    $group = Gtk::AccelGroup.new
    menu = nil
    menu_items.each do |mi|
      if mi[0]==nil or menu==nil
        menuitem = Gtk::MenuItem.new(_(mi[2]))
        menubar.append(menuitem)
        menu = Gtk::Menu.new
        menuitem.set_submenu(menu)
      else
        menuitem = create_menu_item(mi)
        menu.append(menuitem)
      end
    end
    $window.add_accel_group($group)
  end

  def self.fill_toolbar(toolbar)
    menu_items.each do |mi|
      stock = mi[1]
      if stock
        command = mi[0]
        label = mi[2]
        if command and (command != '-') and label and (label != '-')
          toggle = nil
          toggle = false if mi[4]
          btn = PandoraGUI.add_tool_btn(toolbar, stock, label, toggle) do |widget, *args|
            do_menu_act(widget)
          end
          btn.name = command
          if (toggle != nil)
            index = nil
            case command
              when 'Listen'
                index = SF_Listen
              when 'Hunt'
                index = SF_Hunt
            end
            if index
              $toggle_buttons[index] = btn
              #btn.signal_emit_stop('clicked')
              #btn.signal_emit_stop('toggled')
              #btn.signal_connect('clicked') do |*args|
              #  p args
              #  true
              #end
            end
          end
        end
      end
    end
  end

  $cvpaned = nil

  class CaptchaHPaned < Gtk::HPaned
    attr_accessor :csw

    def initialize(first_child)
      super()
      @first_child = first_child
      self.pack1(@first_child, true, true)
      @csw = nil
    end

    def show_captcha(srckey, captcha_buf=nil, clue_text=nil, node=nil)
      res = nil
      if captcha_buf
        @vbox = Gtk::VBox.new
        vbox = @vbox

        @csw = Gtk::ScrolledWindow.new(nil, nil)
        csw = @csw
        csw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
        csw.shadow_type = Gtk::SHADOW_IN
        csw.add(vbox)
        csw.border_width = 1;

        pixbuf_loader = Gdk::PixbufLoader.new
        pixbuf_loader.last_write(captcha_buf) if captcha_buf

        label = Gtk::Label.new(_('Far node'))
        vbox.pack_start(label, false, false, 2)
        entry = Gtk::Entry.new
        node_text = PandoraKernel.bytes_to_hex(srckey)
        node_text = node if (not node_text) or (node_text=='')
        node_text ||= ''
        entry.text = node_text
        entry.editable = false
        vbox.pack_start(entry, false, false, 2)

        image = Gtk::Image.new(pixbuf_loader.pixbuf)
        vbox.pack_start(image, false, false, 2)

        clue_text ||= ''
        clue, length, symbols = clue_text.split('|')
        #p '    [clue, length, symbols]='+[clue, length, symbols].inspect

        len = 0
        begin
          len = length.to_i if length
        rescue
        end

        label = Gtk::Label.new(_('Enter text from picture'))
        vbox.pack_start(label, false, false, 2)

        captcha_entry = PandoraGUI::MaskEntry.new
        captcha_entry.max_length = len
        if symbols
          mask = symbols.downcase+symbols.upcase
          captcha_entry.mask = mask
        end

        okbutton = Gtk::Button.new(Gtk::Stock::OK)
        okbutton.signal_connect('clicked') do
          text = captcha_entry.text
          yield(text) if block_given?
          show_captcha(srckey)
        end

        cancelbutton = Gtk::Button.new(Gtk::Stock::CANCEL)
        cancelbutton.signal_connect('clicked') do
          yield(false) if block_given?
          show_captcha(srckey)
        end

        captcha_entry.signal_connect('key-press-event') do |widget, event|
          if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
            okbutton.activate
            true
          elsif (Gdk::Keyval::GDK_Escape==event.keyval)
            captcha_entry.text = ''
            cancelbutton.activate
            false
          else
            false
          end
        end
        PandoraGUI.hack_enter_bug(captcha_entry)

        ew = 150
        if len>0
          str = label.text
          label.text = 'W'*(len+1)
          ew,lh = label.size_request
          label.text = str
        end

        captcha_entry.width_request = ew
        align = Gtk::Alignment.new(0.5, 0.5, 0.0, 0.0)
        align.add(captcha_entry)
        vbox.pack_start(align, false, false, 2)
        #capdialog.def_widget = entry

        hbox = Gtk::HBox.new
        hbox.pack_start(okbutton, true, true, 2)
        hbox.pack_start(cancelbutton, true, true, 2)

        vbox.pack_start(hbox, false, false, 2)

        if clue
          label = Gtk::Label.new(_(clue))
          vbox.pack_start(label, false, false, 2)
        end
        if length
          label = Gtk::Label.new(_('Length')+'='+length.to_s)
          vbox.pack_start(label, false, false, 2)
        end
        if symbols
          sym_text = _('Symbols')+': '+symbols.to_s
          i = 30
          while i<sym_text.size do
            sym_text = sym_text[0,i]+"\n"+sym_text[i+1..-1]
            i += 31
          end
          label = Gtk::Label.new(sym_text)
          vbox.pack_start(label, false, false, 2)
        end

        csw.border_width = 1;
        csw.set_size_request(250, -1)
        self.border_width = 2
        self.pack2(csw, true, true)  #hpaned3                                      9
        csw.show_all
        full_width = $window.allocation.width
        self.position = full_width-250 #self.max_position #@csw.width_request
        captcha_entry.grab_focus
        res = csw
      else
        #@csw.width_request = @csw.allocation.width
        @csw.destroy
        @csw = nil
        self.position = 0
      end
      res
    end
  end

  # Show main Gtk window
  # RU: Показать главное окно Gtk
  def self.show_main_window
    $window = Gtk::Window.new('Pandora')
    main_icon = nil
    begin
      main_icon = Gdk::Pixbuf.new(File.join($pandora_view_dir, 'pandora.ico'))
    rescue Exception
    end
    if not main_icon
      main_icon = $window.render_icon(Gtk::Stock::HOME, Gtk::IconSize::LARGE_TOOLBAR)
    end
    if main_icon
      $window.icon = main_icon
      Gtk::Window.default_icon = $window.icon
    end

    menubar = Gtk::MenuBar.new
    fill_menubar(menubar)

    toolbar = Gtk::Toolbar.new
    toolbar.toolbar_style = Gtk::Toolbar::Style::ICONS
    fill_toolbar(toolbar)

    $notebook = Gtk::Notebook.new
    $notebook.signal_connect('switch-page') do |widget, page, page_num|
    #$notebook.signal_connect('change-current-page') do |widget, page_num|
      cur_page = $notebook.get_nth_page(page_num)
      if $last_page and (cur_page != $last_page) and ($last_page.is_a? PandoraGUI::TalkScrolledWindow)
        $last_page.init_video_sender(false, true) if not $last_page.area_send.destroyed?
        $last_page.init_video_receiver(false) if not $last_page.area_recv.destroyed?
      end
      if cur_page.is_a? PandoraGUI::TalkScrolledWindow
        cur_page.update_state(false, cur_page)
        cur_page.init_video_receiver(true, true, false) if not cur_page.area_recv.destroyed?
        cur_page.init_video_sender(true, true) if not cur_page.area_send.destroyed?
      end
      $last_page = cur_page
    end

    $view = Gtk::TextView.new
    $view.can_focus = false
    $view.has_focus = false
    $view.receives_default = true
    $view.border_width = 0

    sw = Gtk::ScrolledWindow.new(nil, nil)
    sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
    sw.shadow_type = Gtk::SHADOW_IN
    sw.add($view)
    sw.border_width = 1;
    sw.set_size_request(-1, 40)

    vpaned = Gtk::VPaned.new
    vpaned.border_width = 2
    vpaned.pack1($notebook, true, true)
    vpaned.pack2(sw, false, true)

    $cvpaned = CaptchaHPaned.new(vpaned)
    $cvpaned.position = $cvpaned.max_position

    $statusbar = Gtk::Statusbar.new
    PandoraGUI.set_statusbar_text($statusbar, _('Base directory: ')+$pandora_base_dir)

    add_status_field(SF_Update, 'Not checked') do
      start_updating(true)
    end
    add_status_field(SF_Auth, 'Not logged') do
      do_menu_act('Authorize')
    end
    add_status_field(SF_Listen, 'Not listen') do
      do_menu_act('Listen')
    end
    add_status_field(SF_Hunt, 'No hunt') do
      do_menu_act('Hunt')
    end
    add_status_field(SF_Conn, '0/0/0') do
      do_menu_act('Node')
    end

    vbox = Gtk::VBox.new
    vbox.pack_start(menubar, false, false, 0)
    vbox.pack_start(toolbar, false, false, 0)
    vbox.pack_start($cvpaned, true, true, 0)
    vbox.pack_start($statusbar, false, false, 0)

    $window.add(vbox)

    $window.set_default_size(640, 420)
    $window.maximize
    $window.show_all

    $window.signal_connect('delete-event') do |*args|
      $window.hide
      true
    end

    $statusicon = PandoraGUI::PandoraStatusIcon.new

    $window.signal_connect('destroy') do |window|
      reset_current_key
      $statusicon.visible = false if ($statusicon and (not $statusicon.destroyed?))
      Gtk.main_quit
    end

    $window.signal_connect('key-press-event') do |widget, event|
      if ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?(event.keyval) and event.state.mod1_mask?) or
        ([Gdk::Keyval::GDK_q, Gdk::Keyval::GDK_Q, 1738, 1770].include?(event.keyval) and event.state.control_mask?) #q, Q, й, Й
      then
        Gtk.main_quit
      end
      false
    end

    $window.signal_connect('window-state-event') do |widget, event_window_state|
      if (event_window_state.changed_mask == Gdk::EventWindowState::ICONIFIED) \
        and ((event_window_state.new_window_state & Gdk::EventWindowState::ICONIFIED)>0)
      then
        if $notebook.page >= 0
          sw = $notebook.get_nth_page($notebook.page)
          if sw.is_a? TalkScrolledWindow
            sw.init_video_sender(false, true) if not sw.area_send.destroyed?
            sw.init_video_receiver(false) if not sw.area_recv.destroyed?
          end
        end
        if widget.visible? and widget.active?
          $window.hide
          #$window.skip_taskbar_hint = true
        end
      end
    end

    $base_id = PandoraGUI.get_param('base_id')
    check_update = PandoraGUI.get_param('check_update')
    if (check_update==1) or (check_update==true)
      last_check = PandoraGUI.get_param('last_check')
      last_update = PandoraGUI.get_param('last_update')
      check_interval = PandoraGUI.get_param('check_interval')
      if not check_interval or (check_interval <= 0)
        check_interval = 2
      end
      update_period = PandoraGUI.get_param('update_period')
      if not update_period or (update_period <= 0)
        update_period = 7
      end
      time_now = Time.now.to_i
      need_check = ((time_now - last_check.to_i) >= check_interval*24*3600)
      if (time_now - last_update.to_i) < update_period*24*3600
        set_status_field(SF_Update, 'Updated', need_check)
      elsif need_check
        start_updating(false)
      end
    end

    PandoraGUI.get_exchage_params

    Gtk.main
  end

end


# ====MAIN=======================================================================

# Some module settings
# RU: Некоторые настройки модулей
BasicSocket.do_not_reverse_lookup = true
Thread.abort_on_exception = true

# == Running the Pandora!
# == RU: Запуск Пандоры!
#$lang = 'en'
PandoraKernel.load_language($lang)
PandoraModel.load_model_from_xml($lang)
PandoraGUI.show_main_window
