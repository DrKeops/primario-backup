## AUTOR: Isak Edo Vivancos y Luis Fueris Martin
## NIA: 682405 - 699623
## FICHERO: servidor_gv.exs
## TIEMPO: 10 horas
## DESCRIPCION: fichero del servidor de gestión de vistas de la aplicacion

defmodule ServidorGV do

    @moduledoc """
        modulo del servicio de vistas
    """

    # Tipo estructura de dtos que guarda el estado del servidor de vistas
    # COMPLETAR  con lo campos necesarios para gestionar
    # el estado del gestor de vistas
    #
    # num_vista = vista tentativa
    # primario = primario tentativa
    # secundario = secundario tentativa
    #
    # --------------------------------
    # num_vista_v = vista válida
    # primario_v = primario válido
    # secundario_v = secundario válido
    defstruct num_vista_v: 0, primario_v: :undefined, copia_v: :undefined, 
              num_vista: 0, primario: :undefined, copia: :undefined,
              espera: [], latidos: Map.new(), espera_confirmacion: false


    @tiempo_espera_carga_remota 1000

    @periodo_latido 50

    @latidos_fallidos 4


   @doc """
        Generar un estructura de datos vista inicial
    """
    #### Función que devuelve la vista inicial del Gestor de Vistas
    def vista_inicial() do
        %{num_vista: 0, primario: :undefined, copia: :undefined}
    end

    @doc """
        Poner en marcha el servidor para gestión de vistas
    """
    ### Función [start] de los nodos remotos así como del Gestor de Vistas 
    #   ([init_sv])
    @spec start(String.t, String.t) :: atom
    def start(host, nombre_nodo) do
        nodo = NodoRemoto.start(host, nombre_nodo,__ENV__.file,
                                __MODULE__)

        Node.spawn(nodo, __MODULE__, :init_sv, [])

        nodo
    end
    
    ### Función que devuelve el estado inicial del Gestor de Vistas
    defp struct_inicial() do
        %ServidorGV{}
    end

    #------------------- Funciones privadas

    # Estas 2 primeras deben ser defs para llamadas tipo (MODULE, funcion,[])
    ### Función para inicializar los dos procesos del Gestor de Vistas,
    #   el que se encarga de [bucle_recepcion] y el que se encarga de 
    #   [procesa_situacion_servidores]
    def init_sv() do
        Process.register(self(), :servidor_gv)

        spawn(__MODULE__, :init_monitor, [self()]) # otro proceso concurrente

        #### VUESTRO CODIGO DE INICIALIZACION

        bucle_recepcion(struct_inicial)
       
    end

    ### Función para inicializar el proceso que mantiene la situación de los 
    #   servidores en [procesa_situacion_servidores]
    def init_monitor(pid_principal) do
        send(pid_principal, :procesa_situacion_servidores)
        Process.sleep(@periodo_latido)
        init_monitor(pid_principal)
    end


    ### Función para procesar el ping 0 de los servidores y añadirlos en la 
    # posición de la vista que corresponda
    defp procesar_ping0(vista, nodo_origen) do

        cond do
                
            # No tiene primario
            vista.primario == :undefined ->

                %{vista | primario: nodo_origen, 
                          num_vista: vista.num_vista + 1,
                          latidos: Map.put_new(vista.latidos, 
                                                 nodo_origen, 0)}
             # No tiene secundario
             # El nodo_origen no entre otra vez en copia
             vista.copia == :undefined && vista.primario != nodo_origen ->
                # Actualizamos a vista válida
                %{vista | copia: nodo_origen, 
                          num_vista: vista.num_vista + 1,
                          espera_confirmacion: true,
                          latidos: Map.put_new(vista.latidos, nodo_origen, 0)}

             # Nodos espera
             vista.primario != nodo_origen && vista.copia != nodo_origen &&
             vista.primario != :undefined && vista.copia != :undefined &&
             Enum.find(vista.espera, fn(x) -> nodo_origen == x end) == nil ->
                %{vista | espera: vista.espera ++ [nodo_origen],
                          latidos: Map.put_new(vista.latidos, nodo_origen, 0)}

             # Actualizar nodo primario, copia o espera si se levantan rápido
             # con un ping 0
             true          ->
               # %{vista | latidos: Map.update(vista.latidos, nodo_origen,
               #                 0, fn(_) -> 0 end)}
                nueva = procesar_fallo(vista, nodo_origen)
                procesar_ping0(nueva, nodo_origen)
            end
            
    end


    ### Función para procesar el latido de los servidores y poner a 0 su contador
    defp procesar_latido(vista, nodo_origen) do
        
        # Realizamos esta condición debido a que si un nodo despierta
        # después de haberse caído, enviará un latido con una vista X
        # pero si no está en espera, ni es copia ni primario lo metemos
        # a espera
        nueva_vista = if (Enum.find(vista.espera, 
        fn(x) -> x == nodo_origen end) == nil) 
        && vista.primario != nodo_origen && vista.copia != nodo_origen do
            procesar_ping0(vista, nodo_origen)
        else 
            vista
        end
    
        # Recibimos confirmación del primario mediante el látido,
        # actualizamos la vista
        nueva_vista = if nodo_origen == nueva_vista.primario &&        
        nueva_vista.espera_confirmacion == true do
            
            %{nueva_vista | num_vista_v: nueva_vista.num_vista,
                            primario_v: nueva_vista.primario,
                            copia_v: nueva_vista.copia,
                            espera_confirmacion: false}
        else
            nueva_vista
        end

        %{nueva_vista | latidos: Map.update(nueva_vista.latidos, nodo_origen, 0,
                                              fn(_) -> 0 end)}

    end

    ### Función del bucle de recepción del Gestor de Vistas
    defp bucle_recepcion(vista) do
        nueva_vista = receive do
  			{:latido, nodo_origen, n_vista} ->

                vista = if n_vista == 0  do
                    procesar_ping0(vista, nodo_origen)
                else
                    vista
                end

                vista = if n_vista != -1 do
                    procesar_latido(vista, nodo_origen)
                else 
                    vista
                end
                      
                send({:cliente_gv, nodo_origen}, 
                    {:vista_tentativa, %{num_vista: vista.num_vista,
                     primario: vista.primario,
                     copia: vista.copia},
                               true})
                        # NO DEVOLVÍA LOS MÉTODOS DEL IF
                        # DEVOLVÍA LO DEL SEND
                        vista
                        
                    {:obten_vista, pid} ->
                        
                        resp = if vista.num_vista == vista.num_vista_v do
                                    true
                                else
                                    false
                                end

                        send(pid, {:vista_valida, %{num_vista: vista.num_vista_v,
                             primario: vista.primario_v,
                             copia: vista.copia_v}, resp})
                        vista

                    :procesa_situacion_servidores ->
                        procesar_situacion_servidores(vista)
                    

        end

        bucle_recepcion(nueva_vista)
    end


    ### Funciones auxiliares de [procesar_espera]
    defp sumar_latidos(latidos, []) do latidos end
    defp sumar_latidos(latidos, [h | t]) do
        nuevo_latidos = Map.update(latidos, h, 0, fn(v) -> v + 1 end)
        sumar_latidos(nuevo_latidos, t)
    end

    ### Funciones para procesar el fallo de los nodos en espera
    defp procesar_espera(vista, []) do vista end
    defp procesar_espera(vista, [ h | t]) do

        nueva = cond do
            Map.get(vista.latidos, h) >= @latidos_fallidos ->
                %{vista | latidos: Map.delete(vista.latidos, h),
                                  espera: List.delete(vista.espera, h)}
            true            ->
              vista
        end

        procesar_espera(nueva, t)

    end


    ### Función para procesar el fallo de los distintos servidores
    defp procesar_fallo(vista, nodo_origen) do

        cond do
            vista.copia == nodo_origen && Enum.empty?(vista.espera) ->
                
                %{vista | copia: :undefined,
                        num_vista: vista.num_vista + 1, 
                        latidos: Map.delete(vista.latidos, vista.copia)}

            vista.copia == nodo_origen ->
                
                %{vista | copia:  hd(vista.espera), 
                        num_vista: vista.num_vista + 1, 
                        espera: tl(vista.espera),
                        latidos: Map.delete(vista.latidos, vista.copia),
                        espera_confirmacion: true}
            
            vista.primario == nodo_origen && Enum.empty?(vista.espera) ->
                
                %{vista | primario: vista.copia, copia: :undefined,
                        num_vista: vista.num_vista + 1, 
                        latidos: Map.delete(vista.latidos, vista.primario)}

            vista.primario == nodo_origen ->
                
                %{vista | primario: vista.copia, copia: hd(vista.espera), 
                        num_vista: vista.num_vista + 1, 
                        espera: tl(vista.espera),
                        latidos: Map.delete(vista.latidos, vista.primario),
                        espera_confirmacion: true}

            true            ->
                vista

	    end
    end

    ### Función para procesar la situación de los servidores
    def procesar_situacion_servidores(vista) do

        nueva = %{vista | latidos: sumar_latidos(vista.latidos, 
                                           Map.keys(vista.latidos))}
        
        nueva = procesar_espera(nueva, vista.espera)

        # Estado inconsistente
        if ((nueva.espera_confirmacion == true && 
           Map.get(nueva.latidos, nueva.primario) >= @latidos_fallidos) ||
           (Map.get(nueva.latidos, nueva.primario) >= @latidos_fallidos &&
           Map.get(nueva.latidos, nueva.copia) >= @latidos_fallidos &&
           nueva.copia != :undefined)) && nueva.primario != :undefined do
            
            System.halt(:abort)

        end 

        nueva = if Map.get(nueva.latidos, nueva.copia) >= @latidos_fallidos && 
           vista.copia != :undefined do
            procesar_fallo(nueva, nueva.copia)
        else
            nueva
        end

        if Map.get(nueva.latidos, nueva.primario) >= @latidos_fallidos &&
            vista.primario != :undefined do
            procesar_fallo(nueva, nueva.primario)
        else
            nueva
        end
    
    end
end
