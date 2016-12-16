# AUTOR: Isak Edo Vivancos - Luis Fueris Martín
# NIA: 682405 - 699623
# FICHERO: servidor_gv.exs
# TIEMPO: 6h
# DESCRIPCION: Fichero que encapsula la lógica de la solución de gestor 
# de vistas para la solución de primario/backup 

defmodule ServidorGV do

    @moduledoc """
        modulo del servicio de vistas
    """

    defstruct  num_vista: 0, primario: :undefined, copia: :undefined,
     			num_vistaV: 0, primarioV: :undefined, copiaV: :undefined,
     			espera: [], latidos: Map.new(), esperando_confirmacion: false  

    @tiempo_espera_carga_remota 1000

    @periodo_latido 50

    @latidos_fallidos 4


    @doc """
        Generar un vista inicial
    """
    def vista_inicial() do
       	%{num_vista: 0, primario: :undefined, copia: :undefined}
    end

    defp struct_inicial() do
        %ServidorGV{}
    end

    @doc """
        Poner en marcha el servidor para gestión de vistas
    """
    @spec start(String.t, String.t) :: atom
    def start(host, nombre_nodo) do
        nodo = NodoRemoto.start(host, nombre_nodo,__ENV__.file,
                                __MODULE__)

        Node.spawn(nodo, __MODULE__, :init_sv, [])

        nodo
    end


    #------------------- Funciones privadas

    # Estas 2 primeras deben ser defs para llamadas tipo (MODULE, funcion,[])
    def init_sv() do
        Process.register(self(), :servidor_gv)

        spawn(__MODULE__, :init_monitor, [self()]) # otro proceso concurrente

        bucle_recepcion(struct_inicial())
    end

    def init_monitor(pid_principal) do
        send(pid_principal, :procesa_situacion_servidores)
        Process.sleep(@periodo_latido)
        init_monitor(pid_principal)
    end


    defp bucle_recepcion(vista) do
        nueva_vista = receive do
                    {:latido, nodo_origen, n_vista} ->

                        vista = if(n_vista == 0) do
                        	procesar_ping_0(nodo_origen,vista)
                        else vista
                        end
                        vista = if(n_vista > 0) do
                        	procesar_latido(nodo_origen,vista)	
                        else vista
                        end

                        send({:cliente_gv, nodo_origen},
                        	{:vista_tentativa, %{num_vista: vista.num_vista, 
                        		primario: vista.primario,
                        		copia: vista.copia}, true})
                        vista
                
                    {:obten_vista, pid} ->

                        resp = if(vista.num_vista == vista.num_vistaV) do true 
                    	else false end
                        send(pid,{:vista_valida, %{num_vista: vista.num_vistaV, 
                        		primario: vista.primarioV,
                        		copia: vista.copiaV},resp})  
                        vista            

                    :procesa_situacion_servidores ->
                
                        procesar_situacion_servidores(vista)
                        
        end

        bucle_recepcion(nueva_vista)
    end


    defp sumar_latidos(latidos, []) do latidos end
    defp sumar_latidos(latidos,[h | t]) do
    	nuevo_latidos = Map.update(latidos,h,0,fn(v) -> v + 1 end)
    	sumar_latidos(nuevo_latidos,t)
    end

    defp procesar_espera(vista, []) do vista end
    defp procesar_espera(vista,[h | t]) do

    	nueva  = cond do			
			Map.get(vista.latidos,h) == @latidos_fallidos ->

				%{vista | latidos: Map.delete(vista.latidos,h),
							espera: List.delete(vista.espera,h)}
			true -> vista
        end
    	
    	procesar_espera(nueva,t)
    end

    defp procesar_situacion_servidores(vista) do
    	
        nueva = %{vista | latidos: sumar_latidos(vista.latidos,
        										Map.keys(vista.latidos))} 
        
        if (nueva.esperando_confirmacion == true && 
        Map.get(nueva.latidos,nueva.primario) >= @latidos_fallidos ||
        Map.get(nueva.latidos,nueva.primario) >= @latidos_fallidos &&
        Map.get(nueva.latidos,nueva.copia) >= @latidos_fallidos &&
        nueva.copia != :undefined) && nueva.primario != :undefined do
        
        	System.halt(:abort)
        
        end
        
        nueva = procesar_espera(nueva,nueva.espera)	
        
        nueva = if Map.get(nueva.latidos,nueva.copia) >= @latidos_fallidos &&
			nueva.copia != :undefined do

			procesa_fallo(nueva,nueva.copia)
		else nueva		
		end

		if Map.get(nueva.latidos,nueva.primario) >= @latidos_fallidos &&
			nueva.primario != :undefined do
			
			procesa_fallo(nueva,nueva.primario)
		else nueva
		end
    end

    defp procesa_fallo(vista, nodo_origen) do
    	
    	cond do
    		nodo_origen == vista.copia && Enum.empty?(vista.espera) ->

				%{vista | latidos: Map.delete(vista.latidos,vista.copia),
							num_vista: vista.num_vista + 1,
							copia: :undefined}
			
			nodo_origen == vista.copia ->

				%{vista | latidos: Map.delete(vista.latidos,vista.copia),
							num_vista: vista.num_vista + 1,
							copia: hd(vista.espera),
							espera: tl(vista.espera),
							esperando_confirmacion: true}
		
			nodo_origen == vista.primario && Enum.empty?(vista.espera)  ->
				
				%{vista | latidos: Map.delete(vista.latidos,vista.primario),
							num_vista: vista.num_vista + 1,
							primario: vista.copia,
							copia: :undefined}
			
			nodo_origen == vista.primario ->

				%{vista | latidos: Map.delete(vista.latidos,vista.primario),
							num_vista: vista.num_vista + 1,
							primario: vista.copia,
							copia: hd(vista.espera),
							espera: tl(vista.espera),
							esperando_confirmacion: true}
			true -> vista
        end
    end

    defp procesar_ping_0(nodo_origen, vista) do
    	cond do    		
    		vista.primario == nodo_origen || vista.copia == nodo_origen ||
    		Enum.find(vista.espera, fn(x) -> x == nodo_origen end) != nil ->

    			nueva = procesa_fallo(vista,nodo_origen)
    			procesar_ping_0(nodo_origen,nueva)

    		vista.primario == :undefined ->
    			%{vista | primario: nodo_origen, 
    			 num_vista: vista.num_vista + 1,
    			 latidos: Map.put_new(vista.latidos,nodo_origen,0)}

    		vista.copia == :undefined ->
    			%{vista | copia: nodo_origen, num_vista: vista.num_vista + 1,
    			 esperando_confirmacion: true,
    			 latidos: Map.put_new(vista.latidos,nodo_origen,0)}

    		true ->
    			%{vista | espera: vista.espera ++ [nodo_origen],
    			latidos: Map.put_new(vista.latidos,nodo_origen,0)}
    			
		end
	end

	defp procesar_latido(nodo_origen, vista) do
		nueva_vista = if (nodo_origen != vista.primario && 
			nodo_origen != vista.copia &&
			(Enum.find(vista.espera,fn(x) -> x == nodo_origen end)) == nil) do

    		procesar_ping_0(nodo_origen, vista)

    		else vista 
		end

		nueva_vista = if (nodo_origen == nueva_vista.primario && 
			vista.esperando_confirmacion == true) do
		
			%{nueva_vista | primarioV: nueva_vista.primario,
			copiaV: nueva_vista.copia, num_vistaV: nueva_vista.num_vista,
			esperando_confirmacion: false}

			else nueva_vista			
		end

		%{nueva_vista | latidos: Map.update(nueva_vista.latidos,nodo_origen,0,
    													fn(_) -> 0 end)}
	end

end