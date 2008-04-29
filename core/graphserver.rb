require 'webrick'
#require 'xmlrpc/server.rb'
#Clases Vertex y Graph además del graph_core y las funciones shortest_path y shortest_path_retro
require 'graph.rb'
require 'optparse'
require 'cgi'

#Sobrecarga la clase Calendar para a�adir la funcion to_xml
class Calendar
  #Transforma a xml Calendar
  def to_xml
    "<calendar begin_time='#{Time.at(begin_time)}' end_time='#{Time.at(end_time)}' service_ids='#{service_ids.join(", ")}' />"
  end
end

#made a different change over here

#Sobrecarga la clase Link para a�adir la funcion to_xml
class Link
  #Transforma a xml Link
  def to_xml
    "<link/>"
  end
end

#Sobrecarga la clase Street para a�adir la funcion to_xml
class Street
  #Transforma a xml Street
  def to_xml
    "<street name='#{name}' length='#{length}' />"
  end
end

#Sobrecarga la clase TripHopSchedule para a�adir la funcion to_xml
class TripHopSchedule
  #Transforma a xml TripHopSchedule
  def to_xml
    ret = ["<triphopschedule service_id='#{service_id}'>"]
    #Para cada triphop inserta su transformacion a xml
    triphops.each do |triphop|
      #Ret es un Array, << a�ade un elemento al final de este
      ret << triphop.to_xml
    end
    ret << "</triphopschedule>"

    #Convierte el Array a String
    return ret.join
  end
end

#Sobrecarga la clase TripHop para a�adir la funcion to_xml
class TripHop
  SEC_IN_HOUR = 3600
  SEC_IN_MINUTE = 60

  #Transforma a xml TripHop
  def to_xml
    s_depart = "#{sprintf("%02d", depart/SEC_IN_HOUR)}:#{sprintf("%02d", (depart%SEC_IN_HOUR)/SEC_IN_MINUTE)}:#{sprintf("%02d", depart%SEC_IN_MINUTE)}"
    s_arrive = "#{sprintf("%02d", arrive/SEC_IN_HOUR)}:#{sprintf("%02d", (arrive%SEC_IN_HOUR)/SEC_IN_MINUTE)}:#{sprintf("%02d", arrive%SEC_IN_MINUTE)}"
    "<triphop depart='#{s_depart}' arrive='#{s_arrive}' transit='#{transit}' trip_id='#{trip_id}' />"
  end
end

#Sobrecarga la clase State para a�adir la funcion to_xml
class State
  #Transforma a xml State
  def to_xml
    #Abre la cabecera del elemento state
    ret = "<state "
    #Insercion de atributos. Convierte la instancia de State
    #en un hash y, para cada pareja clave-valor
    self.to_hash.each_pair do |name, value|
      if name == "time" then #TODO kludge alert
        #Si la clave es "time", inserta "time='value'"
        #formateando value como tiempo
        ret << "time='#{Time.at( value ).inspect}' "
      else
        #En caso contrario escrive "name='value'"
        #a menos que el objeto value posea un método to_xml
        ret << "#{name}='#{CGI.escape(value.to_s)}' " unless value.public_methods.include? "to_xml"
      end
    end
    #Cierra la cabecera del elemento state
    ret << ">"

    #Insercion de subelementos. Para cada par clave-valor
    #que tenga un metodo to_xml, inserta el resultado de to_xml
    self.to_hash.each_pair do |name, value|
      ret << value.to_xml if value.public_methods.include? "to_xml"
    end

    #Cierra el elemento state, en este caso ya es un String
    #y no necesita convertir de Array a String con join
    ret << "</state>"
  end
end

#Sobrecarga la clase Vertex para a�adir la funcion to_xml
class Vertex
  #Transforma a xml Vertex
  def to_xml
    ret = ["<vertex label='#{label}'>"]
    #La siguiente instruccion es una comparacion del resultado
    #de una asignacion (= en lugar de ==)
    #Si el objeto Vertex tiene payload lo transforma a xml
    if pl=payload then #to avoid calling payload twice. instantiating a variable may actually be more expensive.
      ret << pl.to_xml
    end
    ret << "</vertex>"
    return ret.join
  end
end

#Sobrecarga la clase Edge para a�adir la funcion to_xml
class Edge
  #Transforma a xml Edge, con parametro de entrada verbose
  #con valor por defecto true
  def to_xml verbose=true
    ret = "<edge>"
    #Si verbose=true inserta el payload transformado a xml
    ret << payload.to_xml if verbose
    ret << "</edge>"
  end
end

#Un hash con las opciones por defecto
OPTIONS = { :port => 3003 }

#Con los parametros de la linea de comandos, hacer
ARGV.options do |opts|
  #Obtiene el nombre del script, p.ej. graphserver.rb
  script_name = File.basename($0)
  opts.banner = "Usage: ruby #{script_name} [options]"

  opts.separator ""

  #Si encuentra la opcion -p o --port, se queda el valor en el
  #elemento :port de OPTIONS, en caso contrario imprime un mensaje
  opts.on("-p", "--port=port", Integer,
          "Runs Rails on the specified port.",
          "Default: 3003") { |v| OPTIONS[:port] = v }

  #Si encuentra la opcion -h o --help, muestra el mensaje de ayuda
  opts.on("-h", "--help",
          "Show this help message.") { puts opts; exit }

  #Ni idea!
  opts.parse!
end

class Graphserver
  #Metodo para hacer publica la lectura de la propiedad gg
  attr_reader :gg

  #Metodo que extrae el parametro 'time' de la peticion GET al servidor
  #Caso de no existir, toma el valor de la fecha-hora actual
  def parse_init_state request
    State.new( (request.query['time'] or Time.now) ) #breaks without the extra parens
  end

  #Funcion llamada al hacer Graphserver.new
  def initialize
    #Crea el grafo de clase Graph
    @gg = Graph.create #horrible hack

    #Lanza el servidor en el puerto :port (digo yo)
    @server = WEBrick::HTTPServer.new(:Port => OPTIONS[:port])

    #Genera la respuesta a la peticion GET "/"
    @server.mount_proc( "/" ) do |request, response|
      #Muestra una pagina web con las posibles peticiones a graphserver
      ret = ["Graphserver Web API"]
      ret << "shortest_path?from=FROM&to=TO"
      ret << "all_vertex_labels"
      ret << "outgoing_edges?label=LABEL"
      ret << "walk_edges?label=LABEL&statevar1=STV1&statevar2=STV2..."
      ret << "collapse_edges?label=LABEL&statevar1=STV1&statevar2=STV2..."
      #Transforma el Array en un String de varias lineas de texto
      response.body = ret.join("\n")
    end

    #Genera la respuesta a la peticion GET "/shortest_path"
    @server.mount_proc( "/shortest_path" ) do |request, response|
      from = request.query['from']
      to = request.query['to']
      ret = []

      begin
        #A menos que existan tanto el vertice con id con valor from,
        #como el id con valor to, genera una excepcion de parametros invalidos
        unless  @gg.get_vertex(from) and @gg.get_vertex(to) then raise ArgumentError end

        #Obtiene el parametro 'time' de la peticion GET o lo genera
        init_state = parse_init_state( request )
        vertices, edges = @gg.shortest_path(from, to, init_state )      #Throws RuntimeError if no shortest path found.
        ret << "<?xml version='1.0'?>"
        ret << "<route>"
        #Transforma a XML el primer vertice
        ret << vertices.shift.to_xml
        edges.each do |edge|
          #Para cada enlace, transforma el enlace a XML
          ret << edge.to_xml
          #Pasa al siguiente vertice y lo transforma a XML
          ret << vertices.shift.to_xml
        end
        ret << "</route>"

        #Sentencia tipo catch
        rescue RuntimeError                                               #TODO: change exception type, RuntimeError is too vague.
          ret << "Couldn't find a shortest path from #{from} to #{to}"
        #Sentencia tipo catch
        rescue ArgumentError
          ret << "ERROR: Invalid parameters."
      end

      response.body = ret.join
    end

    #Genera la respuesta a la peticion GET "/all_vertex_labels"
    @server.mount_proc( "/all_vertex_labels" ) do |request, response|
      vlabels = []
      vlabels << "<?xml version='1.0'?>"
      vlabels << "<labels>"
      @gg.vertices.each do |vertex|
        #Para cada vertice escribe su etiqueta
        vlabels << "<label>#{vertex.label}</label>"
      end
      vlabels << "</labels>"
      response.body = vlabels.join
    end

    #Genera la respuesta a la peticion GET "/outgoing_edges"
    @server.mount_proc( "/outgoing_edges" ) do |request, response|
      ret = []

      begin
        #Busca vertice asociado al parametro 'label'
        #Si no existe, genera una excepcion de parametros invalidos
        unless vertex = @gg.get_vertex( request.query['label'] ) then raise ArgumentError end
#      vertex = @gg.get_vertex( request.query['label'] )
        ret << "<?xml version='1.0'?>"
        ret << "<edges>"
        vertex.each_outgoing do |edge|
          ret << "<edge>"
          ret << "<dest>#{edge.to.to_xml}</dest>"
          ret << "<payload>#{edge.payload.to_xml}</payload>"
          ret << "</edge>"
        end
        ret << "</edges>"

        #Sentencia tipo catch
        rescue ArgumentError
          ret << "ERROR: Invalid parameters."
      end

      response.body = ret.join
    end

    #Genera la respuesta a la peticion GET "/walk_edges"
    @server.mount_proc( "/walk_edges" ) do |request, response|
      ret = []
      begin
        #Busca vertice asociado al parametro 'label'
        #Si no existe, genera una excepcion de parametros invalidos
        unless vertex = @gg.get_vertex( request.query['label'] ) then raise ArgumentError end
#        vertex = @gg.get_vertex( request.query['label'] )
        #Obtiene el parametro 'time' de la peticion GET o lo genera automaticamente
        init_state = parse_init_state( request )

        ret << "<?xml version='1.0'?>"
        ret << "<vertex>"
        ret << init_state.to_xml
        ret << "<outgoing_edges>"
        vertex.each_outgoing do |edge|
          ret << "<edge>"
          ret <<   "<destination label='#{edge.to.label}'>"
          if collapsed = edge.payload.collapse( init_state ) then
            ret << collapsed.walk( init_state ).to_xml
          else
            ret << "<state/>"
          end
          ret <<   "</destination>"
          if collapsed then
            ret << "<payload>#{collapsed.to_xml}</payload>"
          else
            ret << "<payload/>"
          end
          ret << "</edge>"
        end
        ret << "</outgoing_edges>"
        ret << "</vertex>"

        #Sentencia tipo catch
        rescue ArgumentError
          ret << "ERROR: Invalid parameters."
      end

      response.body = ret.join
    end

    #Genera la respuesta a la peticion GET "/collapse_edges"
    @server.mount_proc( "/collapse_edges" ) do |request, response|
      vertex = @gg.get_vertex( request.query['label'] )
      init_state = parse_init_state( request )

      ret = ["<?xml version='1.0'?>"]
      ret << "<vertex>"
      ret << init_state.to_xml
      ret << "<outgoing_edges>"
      vertex.each_outgoing do |edge|
        ret << "<edge>"
        ret << "<destination label='#{edge.to.label}' />"
        if collapsed = edge.payload.collapse( init_state ) then
          ret << "<payload>#{collapsed.to_xml}</payload>"
        else
          ret << "<payload/>"
        end
        ret << "</edge>"
      end
      ret << "</outgoing_edges>"
      ret << "</vertex>"

      response.body = ret.join
    end

  end

  #Asigna los parametros de la base de datos
  def database_params= params
    #Comprueba que existe la extensión postgres,
    #si no existe genera un RuntimeError
    begin
      require 'postgres'
    rescue LoadError
      @db_params = nil
      raise
    end

    begin
      #check if database connection works
      conn = PGconn.connect( params[:host],
                             params[:port],
                             params[:options],
                             params[:tty],
                             params[:dbname],
                             params[:login],
                             params[:password] )
      conn.close
    rescue PGError
      @db_params = nil
      raise
    end

    #Si todo ha ido bien, signa los parametros de la base de datos
    @db_params = params
    return true
  end

  #Conecta con la base de datos si existen los parametros de conexion
  def connect_to_database
    unless @db_params then return nil end

    PGconn.connect( @db_params[:host],
                    @db_params[:port],
                    @db_params[:options],
                    @db_params[:tty],
                    @db_params[:dbname],
                    @db_params[:login],
                    @db_params[:password] )
  end

  #may return nil if postgres isn't loaded, or the connection params aren't set
  def conn
    #if @conn exists and is open
    if @conn and begin @conn.status rescue PGError false end then
      return @conn
    else
      return @conn = connect_to_database
    end
  end

  #Inicia Graphserver. Aparentemente, si el servidor cae, lo reinicia
  def start
    trap("INT"){ @server.shutdown }
    @server.start
  end

end