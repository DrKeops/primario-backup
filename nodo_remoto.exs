defmodule NodoRemoto do

    @moduledoc """
        modulo de gestión de ciclo de vida de nodos remotos
    """

    @doc """
        Poner en marcha un nodo VM remoto con ssh
         - Se tiene en consideracion los puertos disponibles,
            debido al cortafuegos, en el laboratorio 1.02
    """
    @spec start(String.t, String.t, String.t, module) :: node
    def start(host, nombre, fichero_programa_cargar, modulo) do
        tiempo_antes = :os.system_time(:milli_seconds)
        System.cmd("ssh", [host,
                    "elixir --name #{nombre}@#{host} --cookie palabrasecreta",
                    "--erl  \'-kernel inet_dist_listen_min 32000\'",
                    "--erl  \'-kernel inet_dist_listen_max 32009\'",
                    "--detached --no-halt #{fichero_programa_cargar}"])

        nodo = String.to_atom(nombre <> "@" <> host) 
        comprobar_funciona(nodo, modulo)
        :io.format("Tiempo puesta en marcha de nodo ~p : ~p~n",
                    [nodo, :os.system_time(:milli_seconds) - tiempo_antes])
        #Resultado es el atomo que forma el nombre completo del nodo Elixir
        nodo
    end

    @doc """
        Parar un nodo VM remoto por la via rapida
    """
    @spec stop(atom) :: no_return
    def stop(nodo) do
        # :rpc.block_call(nodo, :init, :stop, [])   estilo kill -15
        :rpc.call(nodo, :erlang, :halt, []) # estilo kill -9, ahora nos va

        # tambien habría que eliminar epmd, 
        # en el script shell externo
    end

    # Hasta que la VM responda correctamente, se comprueba que funciona
    defp comprobar_funciona(nodo, modulo) do
        # resultado rpc puede ser cualquier valor
        # El correcto es el nombre del modulo
        if :rpc.call(nodo, modulo, :__info__, [:module], 10) != modulo do
            comprobar_funciona(nodo, modulo)
        end
    end

end