Code.require_file("#{__DIR__}/servidor_gv.exs")

defmodule ClienteGV do

    @tiempo_espera_carga_remota 900
    
    @tiempo_espera_de_respuesta 10
    

    @doc """
        Poner en marcha un nodo cliente del servicio de vistas
    """
    @spec start(String.t, String.t, node) :: node
    def start(host, nombre_nodo, nodo_servidor_gv) do

        nodo = NodoRemoto.start(host, nombre_nodo, __ENV__.file,
                                __MODULE__)#fichero en curso

        Node.spawn(nodo, __MODULE__, :init_cl, [nodo_servidor_gv])

        nodo    
    end


    @doc """
        Solicitar al cliente que envie un ping al servidor de vistas
    """
    @spec latido(atom, integer) :: ServidorGV.t_vista
    def latido(nodo_cliente, num_vista) do
        send({:cliente_gv, nodo_cliente}, {:envia_latido, num_vista, self()})

        receive do   # esperar respuesta del ping
            {:vista_tentativa, vista, is_ok?} -> {vista, is_ok?}
        after @tiempo_espera_de_respuesta ->
            {ServidorGV.vista_inicial(), false}
        end
    end


    @doc """
        Solicitar al cliente que envie una petición de obtención de vista válida
    """
    @spec obten_vista(atom) :: {ServidorGV.t_vista, boolean}
    def obten_vista(nodo_cliente) do
        send({:cliente_gv, nodo_cliente}, {:obten_vista, self()})

        receive do   # esperar respuesta del ping
            {:vista_valida, vista, is_ok?} -> 
                {vista, is_ok?}
        after @tiempo_espera_de_respuesta ->
                {ServidorGV.vista_inicial(), false}
        end
    end


    @doc """
        Solicitar al cliente que consiga el primario del servicio de vistas
    """
    @spec primario(atom) :: node
    def primario(nodo_cliente) do
        resultado = obten_vista(nodo_cliente)

        case resultado do
            {vista, true} ->  vista.primario
            
            {_vista, false} -> :undefined
        end        
    end


    # ------------------ Funciones privadas

    def init_cl(nodo_servidor_gv) do
        Process.register(self(), :cliente_gv)
        bucle_recepcion(nodo_servidor_gv)
    end


    defp bucle_recepcion(nodo_servidor_gv) do
        receive do
            {:envia_latido, num_vista, pid_maestro} ->
                procesa_latido(nodo_servidor_gv, num_vista, pid_maestro)

            {:obten_vista, pid_maestro} ->
                procesa_obten_vista(nodo_servidor_gv, pid_maestro)
        end

        bucle_recepcion(nodo_servidor_gv)
    end


    defp procesa_latido(nodo_servidor_gv, num_vista, pid_maestro) do
        send({:servidor_gv, nodo_servidor_gv}, {:latido, Node.self(), num_vista})

        # esperar respuesta del ping
        receive do  {:vista_tentativa, vista, encontrado?} -> 
                        send(pid_maestro, {:vista_tentativa, vista, encontrado?})
        after @tiempo_espera_de_respuesta ->
                    send(pid_maestro, {:vista_tentativa,
                                        ServidorGV.vista_inicial(), false})
        end     
    end


    defp procesa_obten_vista(nodo_servidor_gv, pid_maestro) do
       send({:servidor_gv, nodo_servidor_gv}, {:obten_vista, self()})

        receive do   {:vista_valida, vista, coincide?} -> 
                        send(pid_maestro, {:vista_valida, vista, coincide?})
        after @tiempo_espera_de_respuesta ->
                    send(pid_maestro, {:vista_valida,
                                        ServidorGV.vista_inicial(), false})
        end             
    end

end