## AUTOR: Isak Edo Vivancos y Luis Fueris Martin                                 
## NIA: 682405 - 699623                                                         
## FICHERO: servicio_vistas_test.exs
## TIEMPO: 4 horas 
### DESCRIPCION: fichero pruebas del servidor de vistas del test

# Compilar y cargar ficheros con modulos necesarios
Code.require_file("#{__DIR__}/nodo_remoto.exs")
Code.require_file("#{__DIR__}/servidor_gv.exs")
Code.require_file("#{__DIR__}/cliente_gv.exs")

# Poner en marcha el servicio de tests unitarios con tiempo de vida limitada
# seed: 0 para que la ejecucion de tests no tenga orden aleatorio
ExUnit.start([timeout: 20000, seed: 0]) # milisegundos

defmodule  GestorVistasTest do

    use ExUnit.Case

    # @moduletag timeout 100  para timeouts de todos lo test de este modulo

    @host1 "127.0.0.1"

    @latidos_fallidos 4

    @intervalo_latido 50


    setup_all do
        # Poner en marcha nodos cliente y servidor
        #sv = :"sv@127.0.0.1"
        # c1 = :"c1@127.0.0.1";
        # c2 = :"c2@127.0.0.1";
        # c3 = :"c3@127.0.0.1"
        sv = ServidorGV.start(@host1, "sv")
        c1 = ClienteGV.start(@host1, "c1", sv)
        c2 = ClienteGV.start(@host1, "c2", sv)
        c3 = ClienteGV.start(@host1, "c3", sv)

        sv_nuevo = ServidorGV.start(@host1, "sv_nuevo")
        c4 = ClienteGV.start(@host1, "c4", sv_nuevo)
        c5 = ClienteGV.start(@host1, "c5", sv_nuevo)
        c6 = ClienteGV.start(@host1, "c6", sv_nuevo)

        on_exit fn ->
                    #eliminar_nodos(sv, c1, c2, c3)
                    IO.puts "Finalmente eliminamos nodos"
                    NodoRemoto.stop(sv)
                    NodoRemoto.stop(c1)
                    NodoRemoto.stop(c2)        
                    NodoRemoto.stop(c3)                            

                    NodoRemoto.stop(sv_nuevo)
                    NodoRemoto.stop(c4)
                    NodoRemoto.stop(c5)        
                    NodoRemoto.stop(c6)                            
                end

        {:ok, [sv: sv, c1: c1, c2: c2, c3: c3, 
                 sv_nuevo: sv_nuevo, c4: c4, c5: c5, c6: c6]}
    end


    # Primer test : un primer primario
    test "Primario prematuro", %{c1: c1} do
        IO.puts("Primer test: Primario prematuro ...")

        p = ClienteGV.primario(c1)

        assert p == :undefined

        IO.puts(" ... Superado")
        IO.puts("-------------------------------------------------------------")
    end


    # Segundo test : primer primario
    test "Primer primario", %{c1: c} do
        IO.puts("Segundo test: Primer primario ...")

        primer_primario(c, @latidos_fallidos * 2)
        comprobar_tentativa(c, c, :undefined, 1)
        
        IO.puts(" ... Superado")
        IO.puts("-------------------------------------------------------------")
    end


    # Tercer test : primer nodo en copia
    test "Primer nodo copia", %{c1: c1, c2: c2} do
        IO.puts("Tercer test: Primer nodo copia ...")

        {vista, _} = ClienteGV.latido(c1, -1)  # Solo interesa vista tentativa
        :io.format("Primer nodo copia tentativa ~p~n", [vista])

        primer_nodo_copia(c1, c2, @latidos_fallidos * 2)

        # validamos nueva vista por estar completa
        ClienteGV.latido(c1, vista.num_vista + 1)

        comprobar_valida(c1, c1, c2, vista.num_vista + 1)

        IO.puts(" ... Superado")
        IO.puts("-------------------------------------------------------------")
    end


    ## Cuarto test : Después, Copia (C2) toma el relevo si Primario falla.,
    test "Copia releva primario", %{c2: c2} do
        IO.puts("Cuarto test: copia toma relevo si primario falla ...")

        {vista, _} = ClienteGV.latido(c2, 2)
        copia_releva_primario(c2, vista.num_vista, @latidos_fallidos * 2)
        
        comprobar_tentativa(c2, c2, :undefined, vista.num_vista + 1)

        IO.puts(" ... Superado")    
        IO.puts("-------------------------------------------------------------")

    end

    ## Quinto test : Servidor rearrancado (C1) se convierte en copia.
    test "Servidor rearrancado se conviert en copia", %{c1: c1, c2: c2} do
        IO.puts("Quinto test: Servidor rearrancado se convierte en copia ...")

        {vista, _} = ClienteGV.latido(c2, 2)   # Solo interesa vista tentativa

        servidor_rearranca_a_copia(c1, c2, 2, @latidos_fallidos * 2)

        # validamos nueva vista por estar DE NUEVO completa
        {vista, _} = ClienteGV.latido(c2, vista.num_vista + 1)

        # No es [vista.num_vista + 1] debido a que estamos confirmando la vista en sí
        comprobar_valida(c2, c2, c1, vista.num_vista)

        IO.puts(" ... Superado")
        IO.puts("-------------------------------------------------------------")
     end

    ## Séptimo test : 3er servidor en espera (C3) se convierte en copia
    ##                si primario falla.
    test "Espera a copia", %{c1: c1, c2: c2, c3: c3} do
        IO.puts("Septimo test: 3er servidor en espera se convierte en copia si primario falla ...")
        
        #  Lo ponemos en espera
        ClienteGV.latido(c3, 0)

        {vista, _} = ClienteGV.latido(c2, 4)
        :io.format("Vista recibida: ~p~n", [vista])

        espera_a_copia(c1, c2, c3, vista.num_vista, @latidos_fallidos * 2)

        # validamos nueva vista por estar DE NUEVO completa
        {vista_conf, _} = ClienteGV.latido(c1, vista.num_vista)
        :io.format("Vista confirmada: ~p~n", [vista_conf])

        comprobar_valida(c1, c1, c3, vista.num_vista + 1)

        IO.puts(" ... Superado")
        IO.puts("-------------------------------------------------------------")
    end


    ## Octavo test : Primario rearrancado (C2) es tratado como caido.
    test "rearrancado caido", %{c1: c1, c2: c2, c3: c3} do
        IO.puts("Octavo test: primario rearrancado c2 es tratado como caído ...")
        
        #  Lo ponemos en espera
        ClienteGV.latido(c2, 0)

        {vista, _} = ClienteGV.latido(c1, 5)
        :io.format("Vista recibida: ~p~n", [vista])

        ClienteGV.latido(c1, vista.num_vista)
        ClienteGV.latido(c3, vista.num_vista)
        ClienteGV.latido(c2, vista.num_vista)
        
        # validamos nueva vista por estar DE NUEVO completa
        {vista_conf, _} = ClienteGV.latido(c1, vista.num_vista)

        :io.format("Vista confirmada: ~p~n", [vista_conf])

        comprobar_valida(c1, c1, c3, vista.num_vista)

        IO.puts(" ... Superado")
        IO.puts("-------------------------------------------------------------")

    end
    
    ### Décimo test: rearrancado rápido, coge vista normal, hace tres latidos, 
    #   tres sleep y no debería de haber cambiado nada
    test "rearrancado rapido", %{c1: c1, c2: c2, c3: c3} do
        IO.puts("Decimo test: rearrancado rapido de los nodos")

        rearrancado_rapido(c1,c2,c3)

        IO.puts(" ... Superado")
        IO.puts("-------------------------------------------------------------")        

    end

    ##  Undécimo test: Servidor de vistas espera a que primario confirme vista
    ##          pero este no lo hace.
    ##          Poner C3 como Primario, C1 como Copia, C2 para comprobar
    ##          - C3 no confirma vista en que es primario,
    ##          - Cae, pero C1 no es promocionado porque C3 no confimo !
    test "primario no confirma vista", %{c1: c1, c2: c2, c3: c3} do 
        IO.puts("Undécimo test: primario (c3) no confirma vista, por lo tanto es inválida")

        primario_no_confirma_vista(c1,c2,c3, 8)

        IO.puts(" ... Superado")
        IO.puts("-------------------------------------------------------------")

    end

    ## Duodécimo : Si anteriores servidores caen (Primario  y Copia),
    ##       un nuevo servidor sin inicializar no puede convertirse en primario.
    # sin_inicializar_no(C1, C2, C3),
    test "sin_inicializar_no", %{c4: c4, c5: c5, c6: c6} do

        IO.puts("Duodécimo test: inicializando nuevos servidores c4, c5 y c6...")

        init_nuevos_nodos(c4,c5,c6)

        # Preguntamos a nodo c6, si c4 es primario y c5 es copia
        comprobar_valida(c6,c4,c5,2)

        # Tiramos los dos nodos
        sin_inicializar_no(c4,c5,c6)

        IO.puts(" ... Superado")
        IO.puts("-------------------------------------------------------------")
  
    end

    # -------------------- FUNCIONES DE LOS TEST --------------------------- #

    defp sin_inicializar_no(c4,c5,c6) do

        NodoRemoto.stop(c4)
        NodoRemoto.stop(c5)
        Process.sleep(@intervalo_latido)
        Process.sleep(@intervalo_latido)
        Process.sleep(@intervalo_latido)
        Process.sleep(@intervalo_latido)

        {vista, _} = ClienteGV.latido(c6, 2)
        :io.format("Vista final ~p~n", [vista])

        # GV caído...
        comprobar_valida(c6,:undefined, :undefined, 0)
    end

    defp init_nuevos_nodos(c4,c5,c6) do

        ClienteGV.latido(c4, 0)
        ClienteGV.latido(c5, 0)
        ClienteGV.latido(c6, 0)

        # Confirmamos vista
        ClienteGV.latido(c4, 2)

        {vista, _} = ClienteGV.obten_vista(c6)
        :io.format("Vista con nuevos nodos ~p~n", [vista])

    end

    defp primario_no_confirma_vista(c1, c2, c3, num_vista) do 

        {vista, _} = ClienteGV.latido(c2,num_vista)
        :io.format("Antes de tirar copia: ~p~n", [vista])
        
        ClienteGV.latido(c3,num_vista)
        Process.sleep(@intervalo_latido)
        Process.sleep(@intervalo_latido)

        ClienteGV.latido(c3,num_vista)
        Process.sleep(@intervalo_latido)
        Process.sleep(@intervalo_latido)

        ClienteGV.latido(c1,0)
        
        # Vista tentativa de este test
        {vista, _} = ClienteGV.latido(c2, num_vista)
        
        :io.format("Vista tentativa test: ~p~n", [vista])

        # NO Confirmo vista por lo tanto c2 
        # tendrá que tener la vista válida
        # del anterior test
        {vista, _} = ClienteGV.obten_vista(c2)
        comprobar(c3, c1, num_vista, vista)

        :io.format("Vista valida anterior test: ~p~n", [vista])

        # Tiramos c3 (primario) antes de que confirme
        ClienteGV.latido(c1,vista.num_vista)
        Process.sleep(@intervalo_latido)
        Process.sleep(@intervalo_latido)

        ClienteGV.latido(c1,vista.num_vista)
        Process.sleep(@intervalo_latido)
        Process.sleep(@intervalo_latido)

        # Gestor de vistas caído
        comprobar_valida(c2, :undefined, :undefined, 0)
        
    end

    defp rearrancado_rapido(c1, c2, c3) do
        
        # El GV no se da cuenta de que los nodos se han caído
        Process.sleep(@intervalo_latido)
        Process.sleep(@intervalo_latido)
        Process.sleep(@intervalo_latido)

        # Estos envían ping 0
        ClienteGV.latido(c3,0)
        ClienteGV.latido(c1,0)
        ClienteGV.latido(c2,0)

        # Pido una vista tentativa 
        {vista, _} = ClienteGV.latido(c2, -1)

        :io.format("Vista tentativa en rearrancado rapido ~p~n", [vista])

        # Confirmo vista con el primario
        {vista, _} = ClienteGV.latido(c3, vista.num_vista)

        :io.format("Vista confirmada en rearrancado rapido ~p~n", [vista])

        comprobar_valida(c3, c3, c1, vista.num_vista)

    end

    defp primer_primario(_c, 0) do :fin end
    defp primer_primario(c, x) do

        {vista, _} = ClienteGV.latido(c, 0)

        if vista.primario != c do
            Process.sleep(@intervalo_latido)
            primer_primario(c, x - 1)
        end
    end

    defp primer_nodo_copia(_c1, _c2, 0) do :fin end
    defp primer_nodo_copia(c1, c2, x) do

        # != 0 para no dar por nuevo y < 0 para no validar
        #ClienteGV.latido(c2, -1)  
        {vista, _} = ClienteGV.latido(c2, 0)

        if vista.copia != c2 do
            Process.sleep(@intervalo_latido)
            primer_nodo_copia(c1, c2, x - 1)
        end
    end

    def copia_releva_primario( _, _num_vista_inicial, 0) do :fin end
    def copia_releva_primario(c2, num_vista_inicial, x) do

        {vista, _} = ClienteGV.latido(c2, num_vista_inicial)
        :io.format("copia_releva_primario VISTA: ~p~n", [vista])

        if (vista.primario != c2) or (vista.copia != :undefined) do
            Process.sleep(@intervalo_latido)
            copia_releva_primario(c2, num_vista_inicial, x - 1)
        end

    end

    defp servidor_rearranca_a_copia(_c1, _c2, _num_vista_inicial, 0) do :fin end
    defp servidor_rearranca_a_copia(c1, c2, num_vista_valida, x) do

        ClienteGV.latido(c1, 0)
        {vista, _} = ClienteGV.latido(c2, num_vista_valida)

        if vista.copia != c1 do
            Process.sleep(@intervalo_latido)
            servidor_rearranca_a_copia(c1, c2, num_vista_valida, x - 1)
        end
    end

    defp espera_a_copia(_c1, _c2, _c3, _num_vista_inicial, 0) do :fin end
    defp espera_a_copia(c1, c2, c3, num_vista_valida, x) do

        ClienteGV.latido(c1, num_vista_valida)
        {vista, _} = ClienteGV.latido(c3, num_vista_valida)
        {vista_valida, _} = ClienteGV.latido(c1, num_vista_valida)
        
        :io.format("Vista recibida en espera_a_copia: ~p~n", [vista])
        :io.format("Vista recibida valida en espera_a_copia: ~p~n", [vista_valida])

        if vista.copia != c3 do
            Process.sleep(@intervalo_latido)
            espera_a_copia(c1, c2, c3, num_vista_valida, x - 1)
        end
    end


    ## ----------------------- FUNCIONES DE COMPROBACIÓN -------------------- #
    defp comprobar_tentativa(nodo_cliente, nodo_primario, nodo_copia, n_vista) do
        # Solo interesa vista tentativa
        {vista, _} = ClienteGV.latido(nodo_cliente, -1) 

        comprobar(nodo_primario, nodo_copia, n_vista, vista)        
    end


    defp comprobar_valida(nodo_cliente, nodo_primario, nodo_copia, n_vista) do
        {vista, _ } = ClienteGV.obten_vista(nodo_cliente)
        
        :io.format("SuVista recibida en comprobar_valida: ~p~n", [vista])

        comprobar(nodo_primario, nodo_copia, n_vista, vista)

        assert ClienteGV.primario(nodo_cliente) == nodo_primario
    end


    defp comprobar(nodo_primario, nodo_copia, n_vista, vista) do
        assert vista.primario == nodo_primario 

        assert vista.copia == nodo_copia 

        assert vista.num_vista == n_vista 
    end


end
