CREATE OR REPLACE PACKAGE PKG_NOMINA IS
    -- NOTA: gc_smlmv NO se declara como constante pública aquí
    TYPE t_concepto_liq IS RECORD (
        id_empleado         LIQUIDACION.id_empleado%TYPE,
        id_quincena         LIQUIDACION.id_quincena%TYPE,
        salario_base_q      LIQUIDACION.salario_base_q%TYPE,
        recargos            LIQUIDACION.recargos%TYPE,
        bonificacion        LIQUIDACION.bonificacion%TYPE,
        auxilio_transp      LIQUIDACION.auxilio_transp%TYPE,
        bono_sede           LIQUIDACION.bono_sede%TYPE,
        bruto               LIQUIDACION.bruto%TYPE,
        deduccion_salud     LIQUIDACION.deduccion_salud%TYPE,
        deduccion_pension   LIQUIDACION.deduccion_pension%TYPE,
        fondo_solidaridad   LIQUIDACION.fondo_solidaridad%TYPE,
        embargo             LIQUIDACION.embargo%TYPE,
        libranzas           LIQUIDACION.libranzas%TYPE,
        aporte_voluntario   LIQUIDACION.aporte_voluntario%TYPE,
        total_deducciones   LIQUIDACION.total_deducciones%TYPE,
        neto                LIQUIDACION.neto%TYPE
    );

    -- Tipo tabla asociativa para BULK COLLECT
    TYPE t_lista_liq IS TABLE OF t_concepto_liq INDEX BY PLS_INTEGER;
    
    -- Tipo para IDs
    TYPE t_id_array IS TABLE OF EMPLEADOS.id_empleado%TYPE INDEX BY PLS_INTEGER;

    -- Función pública para obtener el SMLMV (reemplaza a la constante)
    FUNCTION fn_get_smlmv RETURN NUMBER;

    -- Sobrecarga de procedimientos
    PROCEDURE sp_liquidar_quincena(p_id_empleado NUMBER, p_id_quincena VARCHAR2);
    PROCEDURE sp_liquidar_quincena(p_id_quincena VARCHAR2);

    -- Función total neto por sede
    FUNCTION fn_total_nomina_sede(p_cod_sede VARCHAR2, p_id_quincena VARCHAR2) RETURN NUMBER;

    -- Función pipelined (Punto 7)
    TYPE t_liqu_row IS RECORD (
        id_liquidacion      LIQUIDACION.id_liquidacion%TYPE,
        id_empleado         LIQUIDACION.id_empleado%TYPE,
        nombre_empleado     EMPLEADOS.nombre%TYPE,
        cod_sede            SEDES.cod_sede%TYPE,
        id_quincena         LIQUIDACION.id_quincena%TYPE,
        bruto               LIQUIDACION.bruto%TYPE,
        neto                LIQUIDACION.neto%TYPE
    );
    
    TYPE t_liqu_table IS TABLE OF t_liqu_row;
    
    FUNCTION fn_reporte_nomina(p_cod_sede VARCHAR2 DEFAULT NULL, p_tipo_contrato VARCHAR2 DEFAULT NULL)
    RETURN t_liqu_table PIPELINED;

END PKG_NOMINA;

CREATE OR REPLACE PACKAGE BODY PKG_NOMINA IS

    -- Estructura para caché de parámetros
    TYPE t_param_cache IS RECORD (
        smlmv              NUMBER,
        aux_transporte     NUMBER,
        pct_salud          NUMBER,
        pct_pension        NUMBER,
        pct_fondo_solid    NUMBER,
        umbral_fondo_smlmv NUMBER,
        rec_nocturno       NUMBER,
        rec_dominical      NUMBER,
        rec_noct_dom       NUMBER,
        ret_servicios      NUMBER,
        bono_clima_sma     NUMBER,
        aporte_vol_bog     NUMBER
    );
    
    g_param_cache t_param_cache;
    g_cache_loaded BOOLEAN := FALSE;
    
    -- Procedimiento para cargar caché
    PROCEDURE load_param_cache IS
    BEGIN
        IF NOT g_cache_loaded THEN
            SELECT MAX(CASE WHEN cod_parametro = 'SMLMV' THEN valor_numerico END),
                   MAX(CASE WHEN cod_parametro = 'AUX_TRANSPORTE' THEN valor_numerico END),
                   MAX(CASE WHEN cod_parametro = 'PCT_SALUD' THEN valor_numerico END),
                   MAX(CASE WHEN cod_parametro = 'PCT_PENSION' THEN valor_numerico END),
                   MAX(CASE WHEN cod_parametro = 'PCT_FONDO_SOLIDARIDAD' THEN valor_numerico END),
                   MAX(CASE WHEN cod_parametro = 'UMBRAL_FONDO_SMLMV' THEN valor_numerico END),
                   MAX(CASE WHEN cod_parametro = 'RECARGO_NOCTURNO' THEN valor_numerico END),
                   MAX(CASE WHEN cod_parametro = 'RECARGO_DOMINICAL' THEN valor_numerico END),
                   MAX(CASE WHEN cod_parametro = 'RECARGO_NOCT_DOM' THEN valor_numerico END),
                   MAX(CASE WHEN cod_parametro = 'RET_SERVICIOS' THEN valor_numerico END),
                   MAX(CASE WHEN cod_parametro = 'BONO_CLIMA_SMA' THEN valor_numerico END),
                   MAX(CASE WHEN cod_parametro = 'APORTE_VOL_BOG' THEN valor_numerico END)
            INTO g_param_cache.smlmv,
                 g_param_cache.aux_transporte,
                 g_param_cache.pct_salud,
                 g_param_cache.pct_pension,
                 g_param_cache.pct_fondo_solid,
                 g_param_cache.umbral_fondo_smlmv,
                 g_param_cache.rec_nocturno,
                 g_param_cache.rec_dominical,
                 g_param_cache.rec_noct_dom,
                 g_param_cache.ret_servicios,
                 g_param_cache.bono_clima_sma,
                 g_param_cache.aporte_vol_bog
            FROM PARAMETROS;
            
            g_cache_loaded := TRUE;
        END IF;
    END load_param_cache;

    -- =====================================================
    -- FUNCIÓN PÚBLICA: fn_get_smlmv
    -- =====================================================
    FUNCTION fn_get_smlmv RETURN NUMBER IS
    BEGIN
        load_param_cache;
        RETURN g_param_cache.smlmv;
    END fn_get_smlmv;

    -- =====================================================
    -- FUNCIÓN: fn_salario_base_q (PRIVADA)
    -- =====================================================
    FUNCTION fn_salario_base_q(p_id_empleado NUMBER, p_id_quincena VARCHAR2) RETURN NUMBER IS
        v_tipo_contrato EMPLEADOS.tipo_contrato%TYPE;
        v_salario_base  EMPLEADOS.salario_base%TYPE;
        v_horas_normales NUMBER := 0;
        v_resultado     NUMBER := 0;
    BEGIN
        load_param_cache;
        
        SELECT tipo_contrato, salario_base INTO v_tipo_contrato, v_salario_base
        FROM EMPLEADOS WHERE id_empleado = p_id_empleado;
        
        IF v_tipo_contrato = 'PLANTA' THEN
            v_resultado := v_salario_base / 2;
        ELSIF v_tipo_contrato = 'TEMPORAL' THEN
            SELECT NVL(SUM(cantidad_horas), 0) INTO v_horas_normales
            FROM HORAS_TRABAJADAS
            WHERE id_empleado = p_id_empleado AND id_quincena = p_id_quincena AND tipo_hora = 'NORMAL';
            v_resultado := v_salario_base * v_horas_normales;
        ELSIF v_tipo_contrato = 'SERVICIOS' THEN
            v_resultado := (v_salario_base - (v_salario_base * g_param_cache.ret_servicios / 100)) / 2;
        END IF;
        
        RETURN NVL(v_resultado, 0);
    END fn_salario_base_q;

    -- =====================================================
    -- FUNCIÓN: fn_recargos (PRIVADA)
    -- =====================================================
    FUNCTION fn_recargos(p_id_empleado NUMBER, p_id_quincena VARCHAR2) RETURN NUMBER IS
        v_tipo_contrato EMPLEADOS.tipo_contrato%TYPE;
        v_salario_base  EMPLEADOS.salario_base%TYPE;
        v_valor_hora    NUMBER := 0;
        v_total_recargos NUMBER := 0;
        
        CURSOR c_horas IS
            SELECT tipo_hora, cantidad_horas
            FROM HORAS_TRABAJADAS
            WHERE id_empleado = p_id_empleado AND id_quincena = p_id_quincena
              AND tipo_hora IN ('NOCTURNA', 'DOMINICAL', 'NOCTURNA_DOM');
    BEGIN
        load_param_cache;
        
        SELECT tipo_contrato, salario_base INTO v_tipo_contrato, v_salario_base
        FROM EMPLEADOS WHERE id_empleado = p_id_empleado;
        
        IF v_tipo_contrato = 'SERVICIOS' THEN
            RETURN 0;
        END IF;
        
        -- Calcular valor hora
        IF v_tipo_contrato = 'PLANTA' THEN
            v_valor_hora := v_salario_base / 240;
        ELSE -- TEMPORAL
            v_valor_hora := v_salario_base;
        END IF;
        
        FOR r IN c_horas LOOP
            CASE r.tipo_hora
                WHEN 'NOCTURNA' THEN
                    v_total_recargos := v_total_recargos + (r.cantidad_horas * v_valor_hora * g_param_cache.rec_nocturno / 100);
                WHEN 'DOMINICAL' THEN
                    v_total_recargos := v_total_recargos + (r.cantidad_horas * v_valor_hora * g_param_cache.rec_dominical / 100);
                WHEN 'NOCTURNA_DOM' THEN
                    v_total_recargos := v_total_recargos + (r.cantidad_horas * v_valor_hora * g_param_cache.rec_noct_dom / 100);
            END CASE;
        END LOOP;
        
        RETURN NVL(v_total_recargos, 0);
    END fn_recargos;

    -- =====================================================
    -- FUNCIÓN: fn_bonificacion (PRIVADA)
    -- =====================================================
    FUNCTION fn_bonificacion(p_id_empleado NUMBER) RETURN NUMBER IS
        v_fecha_ingreso EMPLEADOS.fecha_ingreso%TYPE;
        v_tipo_contrato EMPLEADOS.tipo_contrato%TYPE;
        v_antiguedad    NUMBER;
        v_porcentaje    NUMBER := 0;
        v_sanciones_6m  NUMBER;
        v_salario_base_q NUMBER;
    BEGIN
        load_param_cache;
        
        SELECT fecha_ingreso, tipo_contrato INTO v_fecha_ingreso, v_tipo_contrato
        FROM EMPLEADOS WHERE id_empleado = p_id_empleado;
        
        -- SERVICIOS no tiene bonificación
        IF v_tipo_contrato = 'SERVICIOS' THEN
            RETURN 0;
        END IF;
        
        -- Calcular antigüedad en años
        v_antiguedad := TRUNC(MONTHS_BETWEEN(SYSDATE, v_fecha_ingreso) / 12);
        
        -- Determinar porcentaje según antigüedad
        IF v_antiguedad >= 3 AND v_antiguedad <= 5 THEN
            v_porcentaje := 3;
        ELSIF v_antiguedad >= 6 AND v_antiguedad <= 10 THEN
            v_porcentaje := 6;
        ELSIF v_antiguedad > 10 THEN
            v_porcentaje := 10;
        ELSE
            v_porcentaje := 0;
        END IF;
        
        -- Verificar sanciones en últimos 6 meses (más de 2 pierde bonificación)
        SELECT COUNT(*) INTO v_sanciones_6m
        FROM SANCIONES
        WHERE id_empleado = p_id_empleado AND fecha_sancion >= ADD_MONTHS(SYSDATE, -6);
        
        IF v_sanciones_6m > 2 THEN
            v_porcentaje := 0;
        END IF;
        
        -- Calcular sobre salario base quincenal
        v_salario_base_q := fn_salario_base_q(p_id_empleado, '2026-Q1-ENE');
        
        RETURN v_salario_base_q * v_porcentaje / 100;
    END fn_bonificacion;

    -- =====================================================
    -- FUNCIÓN: fn_auxilio_transporte (PRIVADA)
    -- =====================================================
    FUNCTION fn_auxilio_transporte(p_id_empleado NUMBER, p_id_quincena VARCHAR2) RETURN NUMBER IS
        v_tipo_contrato EMPLEADOS.tipo_contrato%TYPE;
        v_salario_base  EMPLEADOS.salario_base%TYPE;
        v_salario_mensual NUMBER;
        v_horas_normales NUMBER := 0;
    BEGIN
        load_param_cache;
        
        SELECT tipo_contrato, salario_base INTO v_tipo_contrato, v_salario_base
        FROM EMPLEADOS WHERE id_empleado = p_id_empleado;
        
        -- SERVICIOS no recibe auxilio
        IF v_tipo_contrato = 'SERVICIOS' THEN
            RETURN 0;
        END IF;
        
        -- Calcular salario mensual equivalente
        IF v_tipo_contrato = 'PLANTA' THEN
            v_salario_mensual := v_salario_base;
        ELSE -- TEMPORAL
            SELECT NVL(SUM(cantidad_horas), 0) INTO v_horas_normales
            FROM HORAS_TRABAJADAS
            WHERE id_empleado = p_id_empleado AND id_quincena = p_id_quincena AND tipo_hora = 'NORMAL';
            v_salario_mensual := v_salario_base * v_horas_normales * 2;
        END IF;
        
        -- Verificar si aplica (<= 2 SMLMV)
        IF v_salario_mensual <= 2 * g_param_cache.smlmv THEN
            RETURN g_param_cache.aux_transporte / 2;
        END IF;
        
        RETURN 0;
    END fn_auxilio_transporte;

    -- =====================================================
    -- FUNCIÓN: fn_bono_sede (PRIVADA)
    -- =====================================================
    FUNCTION fn_bono_sede(p_id_empleado NUMBER) RETURN NUMBER IS
        v_cod_sede      EMPLEADOS.cod_sede%TYPE;
        v_tipo_contrato EMPLEADOS.tipo_contrato%TYPE;
    BEGIN
        load_param_cache;
        
        SELECT cod_sede, tipo_contrato INTO v_cod_sede, v_tipo_contrato
        FROM EMPLEADOS WHERE id_empleado = p_id_empleado;
        
        -- Solo PLANTA y TEMPORAL, solo sede SMA
        IF v_tipo_contrato IN ('PLANTA', 'TEMPORAL') AND v_cod_sede = 'SMA' THEN
            RETURN g_param_cache.bono_clima_sma;
        END IF;
        
        RETURN 0;
    END fn_bono_sede;

    -- =====================================================
    -- FUNCIÓN: fn_bruto (PRIVADA)
    -- =====================================================
    FUNCTION fn_bruto(p_id_empleado NUMBER, p_id_quincena VARCHAR2) RETURN NUMBER IS
        v_salario_base_q NUMBER;
        v_recargos       NUMBER;
        v_bonificacion   NUMBER;
        v_auxilio        NUMBER;
        v_bono           NUMBER;
    BEGIN
        v_salario_base_q := fn_salario_base_q(p_id_empleado, p_id_quincena);
        v_recargos := fn_recargos(p_id_empleado, p_id_quincena);
        v_bonificacion := fn_bonificacion(p_id_empleado);
        v_auxilio := fn_auxilio_transporte(p_id_empleado, p_id_quincena);
        v_bono := fn_bono_sede(p_id_empleado);
        
        RETURN NVL(v_salario_base_q, 0) + NVL(v_recargos, 0) + NVL(v_bonificacion, 0) + 
               NVL(v_auxilio, 0) + NVL(v_bono, 0);
    END fn_bruto;

    -- =====================================================
    -- FUNCIÓN: fn_deducciones (PRIVADA)
    -- =====================================================
    TYPE t_deducciones IS RECORD (
        salud           NUMBER,
        pension         NUMBER,
        fondo_solid     NUMBER,
        embargo         NUMBER,
        libranzas       NUMBER,
        aporte_vol      NUMBER,
        total           NUMBER
    );
    
    FUNCTION fn_deducciones(p_id_empleado NUMBER, p_bruto NUMBER, p_id_quincena VARCHAR2) RETURN t_deducciones IS
        v_result t_deducciones;
        v_bruto_mensual NUMBER;
        v_base_embargo NUMBER;
        v_porc_embargo NUMBER := 0;
        v_tipo_contrato EMPLEADOS.tipo_contrato%TYPE;
        v_cod_sede EMPLEADOS.cod_sede%TYPE;
        v_acepta_aporte EMPLEADOS.acepta_aporte_vol%TYPE;
    BEGIN
        load_param_cache;
        
        -- Inicializar
        v_result.salud := 0;
        v_result.pension := 0;
        v_result.fondo_solid := 0;
        v_result.embargo := 0;
        v_result.libranzas := 0;
        v_result.aporte_vol := 0;
        
        -- 1. Salud
        v_result.salud := p_bruto * g_param_cache.pct_salud / 100;
        
        -- 2. Pensión
        v_result.pension := p_bruto * g_param_cache.pct_pension / 100;
        
        -- 3. Fondo de solidaridad
        v_bruto_mensual := p_bruto * 2;
        IF v_bruto_mensual > g_param_cache.umbral_fondo_smlmv * g_param_cache.smlmv THEN
            v_result.fondo_solid := p_bruto * g_param_cache.pct_fondo_solid / 100;
        END IF;
        
        -- 4. Embargos
        SELECT NVL(SUM(porcentaje), 0) INTO v_porc_embargo
        FROM EMBARGOS
        WHERE id_empleado = p_id_empleado AND estado = 'ACTIVO';
        
        v_base_embargo := p_bruto - v_result.salud - v_result.pension - v_result.fondo_solid;
        v_result.embargo := v_base_embargo * v_porc_embargo / 100;
        
        -- 5. Libranzas (cuota_mensual / 2)
        SELECT NVL(SUM(cuota_mensual), 0) INTO v_result.libranzas
        FROM LIBRANZAS
        WHERE id_empleado = p_id_empleado AND estado = 'ACTIVA';
        v_result.libranzas := v_result.libranzas / 2;
        
        -- 6. Aporte voluntario (solo Bogotá)
        SELECT tipo_contrato, cod_sede, acepta_aporte_vol INTO v_tipo_contrato, v_cod_sede, v_acepta_aporte
        FROM EMPLEADOS WHERE id_empleado = p_id_empleado;
        
        IF v_tipo_contrato IN ('PLANTA', 'TEMPORAL') AND v_cod_sede = 'BOG' AND v_acepta_aporte = 'S' THEN
            v_result.aporte_vol := g_param_cache.aporte_vol_bog;
        END IF;
        
        -- Total deducciones
        v_result.total := v_result.salud + v_result.pension + v_result.fondo_solid + 
                          v_result.embargo + v_result.libranzas + v_result.aporte_vol;
        
        RETURN v_result;
    END fn_deducciones;

    -- =====================================================
    -- PROCEDIMIENTO: sp_liquidar_quincena (un empleado)
    -- =====================================================
    PROCEDURE sp_liquidar_quincena(p_id_empleado NUMBER, p_id_quincena VARCHAR2) IS
        v_empleado_exist NUMBER;
        v_estado EMPLEADOS.estado%TYPE;
        v_ya_liquidado NUMBER;
        v_bruto NUMBER;
        v_deducciones t_deducciones;
        v_neto NUMBER;
        v_liquidacion LIQUIDACION%ROWTYPE;
    BEGIN
        -- Validar que exista el empleado
        SELECT COUNT(*) INTO v_empleado_exist FROM EMPLEADOS WHERE id_empleado = p_id_empleado;
        IF v_empleado_exist = 0 THEN
            RAISE_APPLICATION_ERROR(-20001, 'Empleado no encontrado: ' || p_id_empleado);
        END IF;
        
        -- Validar que esté activo
        SELECT estado INTO v_estado FROM EMPLEADOS WHERE id_empleado = p_id_empleado;
        IF v_estado != 'ACTIVO' THEN
            RAISE_APPLICATION_ERROR(-20002, 'Empleado no activo: estado = ' || v_estado);
        END IF;
        
        -- Validar que no exista liquidación previa
        SELECT COUNT(*) INTO v_ya_liquidado FROM LIQUIDACION 
        WHERE id_empleado = p_id_empleado AND id_quincena = p_id_quincena;
        IF v_ya_liquidado > 0 THEN
            RAISE_APPLICATION_ERROR(-20003, 'Liquidación ya existe para empleado ' || p_id_empleado || ' quincena ' || p_id_quincena);
        END IF;
        
        -- Calcular bruto
        v_bruto := fn_bruto(p_id_empleado, p_id_quincena);
        
        -- Calcular deducciones
        v_deducciones := fn_deducciones(p_id_empleado, v_bruto, p_id_quincena);
        
        -- Calcular neto inicial
        v_neto := v_bruto - v_deducciones.total;
        
        -- Manejo de neto negativo (ajustes)
        IF v_neto < 0 THEN
            -- Ajustar embargo a 0
            v_deducciones.embargo := 0;
            v_deducciones.total := v_deducciones.salud + v_deducciones.pension + v_deducciones.fondo_solid + 
                                   v_deducciones.embargo + v_deducciones.libranzas + v_deducciones.aporte_vol;
            v_neto := v_bruto - v_deducciones.total;
            
            -- Si sigue negativo, ajustar libranzas a 0
            IF v_neto < 0 THEN
                v_deducciones.libranzas := 0;
                v_deducciones.total := v_deducciones.salud + v_deducciones.pension + v_deducciones.fondo_solid + 
                                       v_deducciones.embargo + v_deducciones.libranzas + v_deducciones.aporte_vol;
                v_neto := v_bruto - v_deducciones.total;
                
                -- Log de alerta
                sp_log_nomina('ALERTA_NETO_NEGATIVO', 
                              'Empleado ' || p_id_empleado || ' neto negativo después de ajustes: ' || v_neto,
                              0, 1, 0);
            END IF;
        END IF;
        
        -- Insertar en LIQUIDACION
        INSERT INTO LIQUIDACION VALUES (
            SEQ_LIQUIDACION.NEXTVAL,
            p_id_empleado,
            p_id_quincena,
            fn_salario_base_q(p_id_empleado, p_id_quincena),
            fn_recargos(p_id_empleado, p_id_quincena),
            fn_bonificacion(p_id_empleado),
            fn_auxilio_transporte(p_id_empleado, p_id_quincena),
            fn_bono_sede(p_id_empleado),
            v_bruto,
            v_deducciones.salud,
            v_deducciones.pension,
            v_deducciones.fondo_solid,
            v_deducciones.embargo,
            v_deducciones.libranzas,
            v_deducciones.aporte_vol,
            v_deducciones.total,
            v_neto,
            SYSDATE
        );
        
        COMMIT;
        
        -- Log de éxito
        sp_log_nomina('LIQUIDACION_OK', 'Empleado ' || p_id_empleado || ' liquidado correctamente', 1, 0, v_neto);
        
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            sp_log_nomina('ERROR_LIQUIDACION', SQLERRM, 0, 1, 0);
            RAISE;
    END sp_liquidar_quincena;

    -- =====================================================
    -- PROCEDIMIENTO: sp_liquidar_quincena (todos los empleados)
    -- =====================================================
    PROCEDURE sp_liquidar_quincena(p_id_quincena VARCHAR2) IS
        v_ids t_id_array;
        v_liquidaciones t_lista_liq;
        v_ok_count NUMBER := 0;
        v_error_count NUMBER := 0;
        v_total_neto NUMBER := 0;
        
        CURSOR c_empleados IS
            SELECT e.id_empleado
            FROM EMPLEADOS e
            WHERE e.estado = 'ACTIVO'
              AND NOT EXISTS (SELECT 1 FROM LIQUIDACION l 
                              WHERE l.id_empleado = e.id_empleado 
                                AND l.id_quincena = p_id_quincena);
    BEGIN
        load_param_cache;
        
        -- BULK COLLECT de empleados a procesar
        OPEN c_empleados;
        FETCH c_empleados BULK COLLECT INTO v_ids;
        CLOSE c_empleados;
        
        -- Procesar cada empleado
        FOR i IN 1..v_ids.COUNT LOOP
            BEGIN
                DECLARE
                    v_bruto NUMBER;
                    v_ded t_deducciones;
                    v_neto NUMBER;
                    v_salario_base_q NUMBER;
                    v_recargos NUMBER;
                    v_bonificacion NUMBER;
                    v_auxilio NUMBER;
                    v_bono NUMBER;
                BEGIN
                    v_salario_base_q := fn_salario_base_q(v_ids(i), p_id_quincena);
                    v_recargos := fn_recargos(v_ids(i), p_id_quincena);
                    v_bonificacion := fn_bonificacion(v_ids(i));
                    v_auxilio := fn_auxilio_transporte(v_ids(i), p_id_quincena);
                    v_bono := fn_bono_sede(v_ids(i));
                    v_bruto := v_salario_base_q + v_recargos + v_bonificacion + v_auxilio + v_bono;
                    
                    v_ded := fn_deducciones(v_ids(i), v_bruto, p_id_quincena);
                    v_neto := v_bruto - v_ded.total;
                    
                    -- Manejo neto negativo
                    IF v_neto < 0 THEN
                        v_ded.embargo := 0;
                        v_ded.total := v_ded.salud + v_ded.pension + v_ded.fondo_solid + 
                                       v_ded.embargo + v_ded.libranzas + v_ded.aporte_vol;
                        v_neto := v_bruto - v_ded.total;
                        
                        IF v_neto < 0 THEN
                            v_ded.libranzas := 0;
                            v_ded.total := v_ded.salud + v_ded.pension + v_ded.fondo_solid + 
                                           v_ded.embargo + v_ded.libranzas + v_ded.aporte_vol;
                            v_neto := v_bruto - v_ded.total;
                        END IF;
                    END IF;
                    
                    v_liquidaciones(i).id_empleado := v_ids(i);
                    v_liquidaciones(i).id_quincena := p_id_quincena;
                    v_liquidaciones(i).salario_base_q := v_salario_base_q;
                    v_liquidaciones(i).recargos := v_recargos;
                    v_liquidaciones(i).bonificacion := v_bonificacion;
                    v_liquidaciones(i).auxilio_transp := v_auxilio;
                    v_liquidaciones(i).bono_sede := v_bono;
                    v_liquidaciones(i).bruto := v_bruto;
                    v_liquidaciones(i).deduccion_salud := v_ded.salud;
                    v_liquidaciones(i).deduccion_pension := v_ded.pension;
                    v_liquidaciones(i).fondo_solidaridad := v_ded.fondo_solid;
                    v_liquidaciones(i).embargo := v_ded.embargo;
                    v_liquidaciones(i).libranzas := v_ded.libranzas;
                    v_liquidaciones(i).aporte_voluntario := v_ded.aporte_vol;
                    v_liquidaciones(i).total_deducciones := v_ded.total;
                    v_liquidaciones(i).neto := v_neto;
                    
                    v_ok_count := v_ok_count + 1;
                    v_total_neto := v_total_neto + v_neto;
                EXCEPTION
                    WHEN OTHERS THEN
                        v_error_count := v_error_count + 1;
                        sp_log_nomina('ERROR_BULK', 'Empleado ' || v_ids(i) || ': ' || SQLERRM, 0, 1, 0);
                END;
            END;
        END LOOP;
        
        -- FORALL para inserción masiva
        FORALL i IN 1..v_liquidaciones.COUNT SAVE EXCEPTIONS
            INSERT INTO LIQUIDACION VALUES (
                SEQ_LIQUIDACION.NEXTVAL,
                v_liquidaciones(i).id_empleado,
                v_liquidaciones(i).id_quincena,
                v_liquidaciones(i).salario_base_q,
                v_liquidaciones(i).recargos,
                v_liquidaciones(i).bonificacion,
                v_liquidaciones(i).auxilio_transp,
                v_liquidaciones(i).bono_sede,
                v_liquidaciones(i).bruto,
                v_liquidaciones(i).deduccion_salud,
                v_liquidaciones(i).deduccion_pension,
                v_liquidaciones(i).fondo_solidaridad,
                v_liquidaciones(i).embargo,
                v_liquidaciones(i).libranzas,
                v_liquidaciones(i).aporte_voluntario,
                v_liquidaciones(i).total_deducciones,
                v_liquidaciones(i).neto,
                SYSDATE
            );
        
        COMMIT;
        
        -- Reporte final
        DBMS_OUTPUT.PUT_LINE('Procesados OK: ' || v_ok_count || ' | Errores: ' || v_error_count);
        
        -- Log masivo
        sp_log_nomina('LIQUIDACION_MASIVA', 'Quincena ' || p_id_quincena, v_ok_count, v_error_count, v_total_neto);
        
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            sp_log_nomina('ERROR_MASIVO', SQLERRM, 0, v_ids.COUNT, 0);
            RAISE;
    END sp_liquidar_quincena;

    -- =====================================================
    -- FUNCIÓN: fn_total_nomina_sede
    -- =====================================================
    FUNCTION fn_total_nomina_sede(p_cod_sede VARCHAR2, p_id_quincena VARCHAR2) RETURN NUMBER IS
        v_total NUMBER := 0;
    BEGIN
        SELECT NVL(SUM(l.neto), 0) INTO v_total
        FROM LIQUIDACION l
        JOIN EMPLEADOS e ON l.id_empleado = e.id_empleado
        WHERE e.cod_sede = p_cod_sede AND l.id_quincena = p_id_quincena;
        
        RETURN v_total;
    END fn_total_nomina_sede;

    -- =====================================================
    -- FUNCIÓN PIPELINED: fn_reporte_nomina
    -- =====================================================
    FUNCTION fn_reporte_nomina(p_cod_sede VARCHAR2 DEFAULT NULL, p_tipo_contrato VARCHAR2 DEFAULT NULL)
    RETURN t_liqu_table PIPELINED IS
        v_sql VARCHAR2(4000);
        v_cursor SYS_REFCURSOR;
        v_rec t_liqu_row;
    BEGIN
        v_sql := 'SELECT l.id_liquidacion, l.id_empleado, e.nombre, e.cod_sede, l.id_quincena, l.bruto, l.neto
                  FROM LIQUIDACION l
                  JOIN EMPLEADOS e ON l.id_empleado = e.id_empleado
                  WHERE 1=1';
        
        IF p_cod_sede IS NOT NULL THEN
            v_sql := v_sql || ' AND e.cod_sede = :sede';
        END IF;
        
        IF p_tipo_contrato IS NOT NULL THEN
            v_sql := v_sql || ' AND e.tipo_contrato = :tipo';
        END IF;
        
        OPEN v_cursor FOR v_sql USING p_cod_sede, p_tipo_contrato;
        
        LOOP
            FETCH v_cursor INTO v_rec.id_liquidacion, v_rec.id_empleado, v_rec.nombre_empleado, 
                               v_rec.cod_sede, v_rec.id_quincena, v_rec.bruto, v_rec.neto;
            EXIT WHEN v_cursor%NOTFOUND;
            PIPE ROW(v_rec);
        END LOOP;
        
        CLOSE v_cursor;
        RETURN;
    END fn_reporte_nomina;

    -- =====================================================
    -- PROCEDIMIENTO: sp_log_nomina (AUTONOMOUS_TRANSACTION)
    -- =====================================================
    PROCEDURE sp_log_nomina(p_operation VARCHAR2, p_detalle VARCHAR2, 
                            p_empleados_ok NUMBER DEFAULT 0, 
                            p_empleados_error NUMBER DEFAULT 0, 
                            p_monto_total NUMBER DEFAULT 0) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO LOG_NOMINA (id_log, fecha_hora, operacion, usuario, detalle, empleados_ok, empleados_error/