CREATE OR REPLACE PACKAGE PKG_NOMINA IS

    -- =================================================================
    -- TIPOS PÚBLICOS
    -- =================================================================
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

    TYPE t_lista_liq IS TABLE OF t_concepto_liq INDEX BY PLS_INTEGER;
    TYPE t_id_array IS TABLE OF EMPLEADOS.id_empleado%TYPE INDEX BY PLS_INTEGER;

    -- =================================================================
    -- FUNCIÓN PÚBLICA PARA OBTENER EL SMLMV (reemplaza a la constante)
    -- =================================================================
    FUNCTION fn_get_smlmv RETURN NUMBER;

    -- =================================================================
    -- PROCEDIMIENTOS SOBRECARGADOS
    -- =================================================================
    PROCEDURE sp_liquidar_quincena(p_id_empleado NUMBER, p_id_quincena VARCHAR2);
    PROCEDURE sp_liquidar_quincena(p_id_quincena VARCHAR2);

    -- =================================================================
    -- FUNCIÓN TOTAL NETO POR SEDE
    -- =================================================================
    FUNCTION fn_total_nomina_sede(p_cod_sede VARCHAR2, p_id_quincena VARCHAR2) RETURN NUMBER;

    -- =================================================================
    -- FUNCIÓN PIPELINED (Punto 7)
    -- =================================================================
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
    
    FUNCTION fn_reporte_nomina(p_cod_sede VARCHAR2 DEFAULT NULL, 
                               p_tipo_contrato VARCHAR2 DEFAULT NULL)
    RETURN t_liqu_table PIPELINED;

END PKG_NOMINA;
/
CREATE OR REPLACE PACKAGE BODY PKG_NOMINA IS

    -- =================================================================
    -- CACHÉ DE PARÁMETROS (privada)
    -- =================================================================
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

    TYPE t_deducciones IS RECORD (
        salud           NUMBER,
        pension         NUMBER,
        fondo_solid     NUMBER,
        embargo         NUMBER,
        libranzas       NUMBER,
        aporte_vol      NUMBER,
        total           NUMBER
    );
    
    g_param_cache t_param_cache;
    g_cache_loaded BOOLEAN := FALSE;

    PROCEDURE sp_log_nomina(p_operation VARCHAR2, p_detalle VARCHAR2, 
                            p_empleados_ok NUMBER DEFAULT 0,
                            p_empleados_error NUMBER DEFAULT 0,
                            p_monto_total NUMBER DEFAULT 0);

    -- =================================================================
    -- CARGA DE PARÁMETROS DESDE TABLA
    -- =================================================================
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

    -- =================================================================
    -- FUNCIÓN PÚBLICA QUE RETORNA EL SMLMV
    -- =================================================================
    FUNCTION fn_get_smlmv RETURN NUMBER IS
    BEGIN
        load_param_cache;
        RETURN g_param_cache.smlmv;
    END fn_get_smlmv;

    -- =================================================================
    -- FUNCIÓN PRIVADA: salario base quincenal
    -- =================================================================
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

    -- =================================================================
    -- FUNCIÓN PRIVADA: recargos
    -- =================================================================
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
        IF v_tipo_contrato = 'SERVICIOS' THEN RETURN 0; END IF;
        IF v_tipo_contrato = 'PLANTA' THEN v_valor_hora := v_salario_base / 240;
        ELSE v_valor_hora := v_salario_base; END IF;
        FOR r IN c_horas LOOP
            CASE r.tipo_hora
                WHEN 'NOCTURNA' THEN v_total_recargos := v_total_recargos + (r.cantidad_horas * v_valor_hora * g_param_cache.rec_nocturno / 100);
                WHEN 'DOMINICAL' THEN v_total_recargos := v_total_recargos + (r.cantidad_horas * v_valor_hora * g_param_cache.rec_dominical / 100);
                WHEN 'NOCTURNA_DOM' THEN v_total_recargos := v_total_recargos + (r.cantidad_horas * v_valor_hora * g_param_cache.rec_noct_dom / 100);
            END CASE;
        END LOOP;
        RETURN NVL(v_total_recargos, 0);
    END fn_recargos;

    -- =================================================================
    -- FUNCIÓN PRIVADA: bonificación (con regla de sanciones)
    -- =================================================================
    FUNCTION fn_bonificacion(p_id_empleado NUMBER) RETURN NUMBER IS
        v_fecha_ingreso EMPLEADOS.fecha_ingreso%TYPE;
        v_tipo_contrato EMPLEADOS.tipo_contrato%TYPE;
        v_antiguedad    NUMBER;
        v_porcentaje    NUMBER := 0;
        v_sanciones_6m  NUMBER;
        v_salario_base_q NUMBER;
    BEGIN
        SELECT fecha_ingreso, tipo_contrato INTO v_fecha_ingreso, v_tipo_contrato
        FROM EMPLEADOS WHERE id_empleado = p_id_empleado;
        IF v_tipo_contrato = 'SERVICIOS' THEN RETURN 0; END IF;
        v_antiguedad := TRUNC(MONTHS_BETWEEN(SYSDATE, v_fecha_ingreso) / 12);
        IF v_antiguedad BETWEEN 3 AND 5 THEN v_porcentaje := 3;
        ELSIF v_antiguedad BETWEEN 6 AND 10 THEN v_porcentaje := 6;
        ELSIF v_antiguedad > 10 THEN v_porcentaje := 10;
        ELSE v_porcentaje := 0; END IF;
        SELECT COUNT(*) INTO v_sanciones_6m
        FROM SANCIONES
        WHERE id_empleado = p_id_empleado AND fecha_sancion >= ADD_MONTHS(SYSDATE, -6);
        IF v_sanciones_6m > 2 THEN v_porcentaje := 0; END IF;
        v_salario_base_q := fn_salario_base_q(p_id_empleado, '2026-Q1-ENE');
        RETURN v_salario_base_q * v_porcentaje / 100;
    END fn_bonificacion;

    -- =================================================================
    -- FUNCIÓN PRIVADA: auxilio de transporte
    -- =================================================================
    FUNCTION fn_auxilio_transporte(p_id_empleado NUMBER, p_id_quincena VARCHAR2) RETURN NUMBER IS
        v_tipo_contrato EMPLEADOS.tipo_contrato%TYPE;
        v_salario_base  EMPLEADOS.salario_base%TYPE;
        v_salario_mensual NUMBER;
        v_horas_normales NUMBER := 0;
    BEGIN
        load_param_cache;
        SELECT tipo_contrato, salario_base INTO v_tipo_contrato, v_salario_base
        FROM EMPLEADOS WHERE id_empleado = p_id_empleado;
        IF v_tipo_contrato = 'SERVICIOS' THEN RETURN 0; END IF;
        IF v_tipo_contrato = 'PLANTA' THEN v_salario_mensual := v_salario_base;
        ELSE
            SELECT NVL(SUM(cantidad_horas), 0) INTO v_horas_normales
            FROM HORAS_TRABAJADAS
            WHERE id_empleado = p_id_empleado AND id_quincena = p_id_quincena AND tipo_hora = 'NORMAL';
            v_salario_mensual := v_salario_base * v_horas_normales * 2;
        END IF;
        IF v_salario_mensual <= 2 * g_param_cache.smlmv THEN
            RETURN g_param_cache.aux_transporte / 2;
        END IF;
        RETURN 0;
    END fn_auxilio_transporte;

    -- =================================================================
    -- FUNCIÓN PRIVADA: bono por sede
    -- =================================================================
    FUNCTION fn_bono_sede(p_id_empleado NUMBER) RETURN NUMBER IS
        v_cod_sede      EMPLEADOS.cod_sede%TYPE;
        v_tipo_contrato EMPLEADOS.tipo_contrato%TYPE;
    BEGIN
        load_param_cache;
        SELECT cod_sede, tipo_contrato INTO v_cod_sede, v_tipo_contrato
        FROM EMPLEADOS WHERE id_empleado = p_id_empleado;
        IF v_tipo_contrato IN ('PLANTA', 'TEMPORAL') AND v_cod_sede = 'SMA' THEN
            RETURN g_param_cache.bono_clima_sma;
        END IF;
        RETURN 0;
    END fn_bono_sede;

    -- =================================================================
    -- FUNCIÓN PRIVADA: bruto total
    -- =================================================================
    FUNCTION fn_bruto(p_id_empleado NUMBER, p_id_quincena VARCHAR2) RETURN NUMBER IS
    BEGIN
        RETURN NVL(fn_salario_base_q(p_id_empleado, p_id_quincena), 0)
             + NVL(fn_recargos(p_id_empleado, p_id_quincena), 0)
             + NVL(fn_bonificacion(p_id_empleado), 0)
             + NVL(fn_auxilio_transporte(p_id_empleado, p_id_quincena), 0)
             + NVL(fn_bono_sede(p_id_empleado), 0);
    END fn_bruto;

    -- =================================================================
    -- FUNCIÓN PRIVADA PARA DEDUCCIONES
    -- =================================================================
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
        v_result.salud := p_bruto * g_param_cache.pct_salud / 100;
        v_result.pension := p_bruto * g_param_cache.pct_pension / 100;
        v_bruto_mensual := p_bruto * 2;
        IF v_bruto_mensual > g_param_cache.umbral_fondo_smlmv * g_param_cache.smlmv THEN
            v_result.fondo_solid := p_bruto * g_param_cache.pct_fondo_solid / 100;
        ELSE
            v_result.fondo_solid := 0;
        END IF;
        SELECT NVL(SUM(porcentaje), 0) INTO v_porc_embargo
        FROM EMBARGOS WHERE id_empleado = p_id_empleado AND estado = 'ACTIVO';
        v_base_embargo := p_bruto - v_result.salud - v_result.pension - v_result.fondo_solid;
        v_result.embargo := v_base_embargo * v_porc_embargo / 100;
        SELECT NVL(SUM(cuota_mensual), 0) INTO v_result.libranzas
        FROM LIBRANZAS WHERE id_empleado = p_id_empleado AND estado = 'ACTIVA';
        v_result.libranzas := v_result.libranzas / 2;
        SELECT tipo_contrato, cod_sede, acepta_aporte_vol INTO v_tipo_contrato, v_cod_sede, v_acepta_aporte
        FROM EMPLEADOS WHERE id_empleado = p_id_empleado;
        IF v_tipo_contrato IN ('PLANTA', 'TEMPORAL') AND v_cod_sede = 'BOG' AND v_acepta_aporte = 'S' THEN
            v_result.aporte_vol := g_param_cache.aporte_vol_bog;
        ELSE
            v_result.aporte_vol := 0;
        END IF;
        v_result.total := v_result.salud + v_result.pension + v_result.fondo_solid
                        + v_result.embargo + v_result.libranzas + v_result.aporte_vol;
        RETURN v_result;
    END fn_deducciones;

    -- =================================================================
    -- PROCEDIMIENTO PARA UN EMPLEADO (con validaciones)
    -- =================================================================
    PROCEDURE sp_liquidar_quincena(p_id_empleado NUMBER, p_id_quincena VARCHAR2) IS
        v_empleado_exist NUMBER;
        v_estado EMPLEADOS.estado%TYPE;
        v_ya_liquidado NUMBER;
        v_bruto NUMBER;
        v_ded t_deducciones;
        v_neto NUMBER;
        v_salario_base_q NUMBER;
        v_recargos NUMBER;
        v_bonificacion NUMBER;
        v_auxilio_transp NUMBER;
        v_bono_sede NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_empleado_exist FROM EMPLEADOS WHERE id_empleado = p_id_empleado;
        IF v_empleado_exist = 0 THEN
            RAISE_APPLICATION_ERROR(-20001, 'Empleado no encontrado: ' || p_id_empleado);
        END IF;
        SELECT estado INTO v_estado FROM EMPLEADOS WHERE id_empleado = p_id_empleado;
        IF v_estado != 'ACTIVO' THEN
            RAISE_APPLICATION_ERROR(-20002, 'Empleado no activo: estado = ' || v_estado);
        END IF;
        SELECT COUNT(*) INTO v_ya_liquidado FROM LIQUIDACION 
        WHERE id_empleado = p_id_empleado AND id_quincena = p_id_quincena;
        IF v_ya_liquidado > 0 THEN
            RAISE_APPLICATION_ERROR(-20003, 'Liquidación ya existe para empleado ' || p_id_empleado || ' quincena ' || p_id_quincena);
        END IF;
        v_bruto := fn_bruto(p_id_empleado, p_id_quincena);
        v_ded := fn_deducciones(p_id_empleado, v_bruto, p_id_quincena);
        v_neto := v_bruto - v_ded.total;
        -- Ajuste por neto negativo
        IF v_neto < 0 THEN
            v_ded.embargo := 0;
            v_ded.total := v_ded.salud + v_ded.pension + v_ded.fondo_solid + v_ded.embargo + v_ded.libranzas + v_ded.aporte_vol;
            v_neto := v_bruto - v_ded.total;
            IF v_neto < 0 THEN
                v_ded.libranzas := 0;
                v_ded.total := v_ded.salud + v_ded.pension + v_ded.fondo_solid + v_ded.embargo + v_ded.libranzas + v_ded.aporte_vol;
                v_neto := v_bruto - v_ded.total;
                sp_log_nomina('ALERTA_NETO_NEGATIVO', 'Empleado ' || p_id_empleado || ' neto: ' || v_neto, 0, 1, 0);
            END IF;
        END IF;
        v_salario_base_q := fn_salario_base_q(p_id_empleado, p_id_quincena);
        v_recargos := fn_recargos(p_id_empleado, p_id_quincena);
        v_bonificacion := fn_bonificacion(p_id_empleado);
        v_auxilio_transp := fn_auxilio_transporte(p_id_empleado, p_id_quincena);
        v_bono_sede := fn_bono_sede(p_id_empleado);
        INSERT INTO LIQUIDACION VALUES (
            SEQ_LIQUIDACION.NEXTVAL, p_id_empleado, p_id_quincena,
            v_salario_base_q,
            v_recargos,
            v_bonificacion,
            v_auxilio_transp,
            v_bono_sede,
            v_bruto, v_ded.salud, v_ded.pension, v_ded.fondo_solid,
            v_ded.embargo, v_ded.libranzas, v_ded.aporte_vol, v_ded.total, v_neto, SYSDATE
        );
        COMMIT;
        sp_log_nomina('LIQUIDACION_OK', 'Empleado ' || p_id_empleado, 1, 0, v_neto);
    EXCEPTION
        WHEN OTHERS THEN ROLLBACK; sp_log_nomina('ERROR_LIQUIDACION', SQLERRM, 0, 1, 0); RAISE;
    END sp_liquidar_quincena;

    -- =================================================================
    -- PROCEDIMIENTO MASIVO CON BULK COLLECT Y FORALL (Punto 6)
    -- =================================================================
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
                              WHERE l.id_empleado = e.id_empleado AND l.id_quincena = p_id_quincena);
    BEGIN
        load_param_cache;
        OPEN c_empleados;
        FETCH c_empleados BULK COLLECT INTO v_ids;
        CLOSE c_empleados;
        FOR i IN 1..v_ids.COUNT LOOP
            BEGIN
                DECLARE
                    v_bruto NUMBER;
                    v_ded t_deducciones;
                    v_neto NUMBER;
                    v_sbq NUMBER; v_rec NUMBER; v_bon NUMBER; v_aux NUMBER; v_bns NUMBER;
                BEGIN
                    v_sbq := fn_salario_base_q(v_ids(i), p_id_quincena);
                    v_rec := fn_recargos(v_ids(i), p_id_quincena);
                    v_bon := fn_bonificacion(v_ids(i));
                    v_aux := fn_auxilio_transporte(v_ids(i), p_id_quincena);
                    v_bns := fn_bono_sede(v_ids(i));
                    v_bruto := v_sbq + v_rec + v_bon + v_aux + v_bns;
                    v_ded := fn_deducciones(v_ids(i), v_bruto, p_id_quincena);
                    v_neto := v_bruto - v_ded.total;
                    IF v_neto < 0 THEN
                        v_ded.embargo := 0;
                        v_ded.total := v_ded.salud + v_ded.pension + v_ded.fondo_solid + v_ded.embargo + v_ded.libranzas + v_ded.aporte_vol;
                        v_neto := v_bruto - v_ded.total;
                        IF v_neto < 0 THEN
                            v_ded.libranzas := 0;
                            v_ded.total := v_ded.salud + v_ded.pension + v_ded.fondo_solid + v_ded.embargo + v_ded.libranzas + v_ded.aporte_vol;
                            v_neto := v_bruto - v_ded.total;
                        END IF;
                    END IF;
                    v_liquidaciones(i).id_empleado := v_ids(i);
                    v_liquidaciones(i).id_quincena := p_id_quincena;
                    v_liquidaciones(i).salario_base_q := v_sbq;
                    v_liquidaciones(i).recargos := v_rec;
                    v_liquidaciones(i).bonificacion := v_bon;
                    v_liquidaciones(i).auxilio_transp := v_aux;
                    v_liquidaciones(i).bono_sede := v_bns;
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
                        sp_log_nomina('ERROR_BULK', 'Emp ' || v_ids(i) || ': ' || SQLERRM, 0, 1, 0);
                END;
            END;
        END LOOP;
        FORALL i IN 1..v_liquidaciones.COUNT SAVE EXCEPTIONS
            INSERT INTO LIQUIDACION VALUES (
                SEQ_LIQUIDACION.NEXTVAL,
                v_liquidaciones(i).id_empleado, v_liquidaciones(i).id_quincena,
                v_liquidaciones(i).salario_base_q, v_liquidaciones(i).recargos,
                v_liquidaciones(i).bonificacion, v_liquidaciones(i).auxilio_transp,
                v_liquidaciones(i).bono_sede, v_liquidaciones(i).bruto,
                v_liquidaciones(i).deduccion_salud, v_liquidaciones(i).deduccion_pension,
                v_liquidaciones(i).fondo_solidaridad, v_liquidaciones(i).embargo,
                v_liquidaciones(i).libranzas, v_liquidaciones(i).aporte_voluntario,
                v_liquidaciones(i).total_deducciones, v_liquidaciones(i).neto, SYSDATE
            );
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Procesados OK: ' || v_ok_count || ' | Errores: ' || v_error_count);
        sp_log_nomina('LIQUIDACION_MASIVA', 'Quincena ' || p_id_quincena, v_ok_count, v_error_count, v_total_neto);
    EXCEPTION
        WHEN OTHERS THEN ROLLBACK; sp_log_nomina('ERROR_MASIVO', SQLERRM, 0, v_ids.COUNT, 0); RAISE;
    END sp_liquidar_quincena;

    -- =================================================================
    -- FUNCIÓN TOTAL NETO POR SEDE
    -- =================================================================
    FUNCTION fn_total_nomina_sede(p_cod_sede VARCHAR2, p_id_quincena VARCHAR2) RETURN NUMBER IS
        v_total NUMBER;
    BEGIN
        SELECT NVL(SUM(l.neto), 0) INTO v_total
        FROM LIQUIDACION l JOIN EMPLEADOS e ON l.id_empleado = e.id_empleado
        WHERE e.cod_sede = p_cod_sede AND l.id_quincena = p_id_quincena;
        RETURN v_total;
    END fn_total_nomina_sede;

    -- =================================================================
    -- FUNCIÓN PIPELINED (Punto 7)
    -- =================================================================
    FUNCTION fn_reporte_nomina(p_cod_sede VARCHAR2 DEFAULT NULL, 
                           p_tipo_contrato VARCHAR2 DEFAULT NULL)
RETURN t_liqu_table PIPELINED IS
    v_sql VARCHAR2(4000);
    v_cursor SYS_REFCURSOR;
    v_rec t_liqu_row;
BEGIN
    v_sql := 'SELECT l.id_liquidacion, l.id_empleado, e.nombre, e.cod_sede, l.id_quincena, l.bruto, l.neto
              FROM LIQUIDACION l 
              JOIN EMPLEADOS e ON l.id_empleado = e.id_empleado
              WHERE ( :sede IS NULL OR e.cod_sede = :sede )
                AND ( :tipo IS NULL OR e.tipo_contrato = :tipo )';
    
    OPEN v_cursor FOR v_sql USING p_cod_sede, p_cod_sede, p_tipo_contrato, p_tipo_contrato;
    -- Nota: cada bind variable debe aparecer tantas veces como se use, y se le pasa el mismo valor.
    -- En este caso :sede aparece dos veces, por eso pasamos p_cod_sede dos veces.
    
    LOOP
        FETCH v_cursor INTO v_rec.id_liquidacion, v_rec.id_empleado, v_rec.nombre_empleado, 
                            v_rec.cod_sede, v_rec.id_quincena, v_rec.bruto, v_rec.neto;
        EXIT WHEN v_cursor%NOTFOUND;
        PIPE ROW(v_rec);
    END LOOP;
    CLOSE v_cursor;
    RETURN;
END fn_reporte_nomina;

    -- =================================================================
    -- PROCEDIMIENTO DE LOG CON AUTONOMOUS TRANSACTION (Punto 8)
    -- =================================================================
    PROCEDURE sp_log_nomina(p_operation VARCHAR2, p_detalle VARCHAR2, 
                            p_empleados_ok NUMBER DEFAULT 0, 
                            p_empleados_error NUMBER DEFAULT 0, 
                            p_monto_total NUMBER DEFAULT 0) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO LOG_NOMINA (id_log, fecha_hora, operacion, usuario, detalle, empleados_ok, empleados_error, monto_total)
        VALUES (SEQ_LOG.NEXTVAL, SYSTIMESTAMP, p_operation, USER, p_detalle, p_empleados_ok, p_empleados_error, p_monto_total);
        COMMIT;
    END sp_log_nomina;

-- =================================================================
-- BLOQUE DE INICIALIZACIÓN DEL PACKAGE (solo carga caché)
-- =================================================================
BEGIN
    load_param_cache;
END PKG_NOMINA;
/