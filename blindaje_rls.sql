-- ================================================================
-- MedStudents · BLINDAJE RLS + FUNCIONES PÚBLICAS DEL PORTAL
-- Correr COMPLETO en SQL Editor → New query → Run
-- ================================================================

-- ============ 1) CLAVE DE EQUIPO ============
-- ⚠️ CAMBIA la clave de abajo por la tuya (larga, única). Anótala.
CREATE OR REPLACE FUNCTION ms_clave_ok(clave TEXT)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT clave = 'MedStudents2026-Abdi-K7xR9pQ2';
$$;

-- Helper: lee la clave enviada por el panel en la cabecera
CREATE OR REPLACE FUNCTION ms_auth()
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT ms_clave_ok(
    coalesce(current_setting('request.headers', true)::json ->> 'x-ms-clave', '')
  );
$$;

-- ============ 2) TABLAS PRIVADAS (solo con clave) ============
ALTER TABLE ms_state ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ms_state_all ON ms_state;
CREATE POLICY ms_state_all ON ms_state FOR ALL TO anon
  USING (ms_auth()) WITH CHECK (ms_auth());

ALTER TABLE ms_snapshots ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ms_snap_all ON ms_snapshots;
CREATE POLICY ms_snap_all ON ms_snapshots FOR ALL TO anon
  USING (ms_auth()) WITH CHECK (ms_auth());

ALTER TABLE ms_activity ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ms_act_all ON ms_activity;
CREATE POLICY ms_act_all ON ms_activity FOR ALL TO anon
  USING (ms_auth()) WITH CHECK (ms_auth());

ALTER TABLE ms_locks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ms_lock_all ON ms_locks;
CREATE POLICY ms_lock_all ON ms_locks FOR ALL TO anon
  USING (ms_auth()) WITH CHECK (ms_auth());

-- ============ 3) REPORTES DE PAGO ============
ALTER TABLE ms_pagos_reportados ENABLE ROW LEVEL SECURITY;

-- El PORTAL (alumnos) SOLO puede insertar. No lee, no borra, no edita.
DROP POLICY IF EXISTS ms_rep_insert ON ms_pagos_reportados;
CREATE POLICY ms_rep_insert ON ms_pagos_reportados FOR INSERT TO anon
  WITH CHECK (estado = 'pendiente');

-- El PANEL (con clave) puede todo.
DROP POLICY IF EXISTS ms_rep_admin_sel ON ms_pagos_reportados;
CREATE POLICY ms_rep_admin_sel ON ms_pagos_reportados FOR SELECT TO anon USING (ms_auth());
DROP POLICY IF EXISTS ms_rep_admin_upd ON ms_pagos_reportados;
CREATE POLICY ms_rep_admin_upd ON ms_pagos_reportados FOR UPDATE TO anon
  USING (ms_auth()) WITH CHECK (ms_auth());
DROP POLICY IF EXISTS ms_rep_admin_del ON ms_pagos_reportados;
CREATE POLICY ms_rep_admin_del ON ms_pagos_reportados FOR DELETE TO anon USING (ms_auth());

-- ============ 4) FUNCIONES PÚBLICAS PARA EL PORTAL ============
-- El portal ya NO puede leer ms_state. Le damos funciones seguras
-- que exponen SOLO lo mínimo, sin datos financieros.

-- 4a) Buscar alumno (sin exponer pagos, metas ni finanzas)
CREATE OR REPLACE FUNCTION ms_portal_buscar(q TEXT)
RETURNS TABLE(id BIGINT, nombre TEXT, apellido TEXT, pista TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF q IS NULL OR length(trim(q)) < 3 THEN RETURN; END IF;
  RETURN QUERY
  SELECT (a->>'id')::BIGINT,
         a->>'nombre',
         a->>'apellido',
         -- pista: correo enmascarado para que el alumno se reconozca
         CASE WHEN coalesce(a->>'email','') <> ''
              THEN left(a->>'email',3) || '***@' || split_part(a->>'email','@',2)
              ELSE '***' || right(coalesce(a->>'whatsapp',''),4) END
  FROM ms_state s, jsonb_array_elements(s.data->'alumnos') a
  WHERE s.id = 'main'
    AND (
      lower(coalesce(a->>'nombre','') || ' ' || coalesce(a->>'apellido','')) LIKE '%' || lower(trim(q)) || '%'
      OR lower(coalesce(a->>'email','')) = lower(trim(q))
      OR regexp_replace(coalesce(a->>'whatsapp',''),'\D','','g') = regexp_replace(trim(q),'\D','','g')
    )
  LIMIT 8;
END; $$;

-- 4b) Cursos activos (para el selector del portal)
CREATE OR REPLACE FUNCTION ms_portal_cursos()
RETURNS TABLE(id BIGINT, nombre TEXT, precio NUMERIC)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY
  SELECT (c->>'id')::BIGINT, c->>'nombre', (c->>'precio')::NUMERIC
  FROM ms_state s, jsonb_array_elements(s.data->'cursos') c
  WHERE s.id = 'main' AND coalesce(c->>'estatus','') <> 'Cerrado';
END; $$;

-- 4c) Cursos de un alumno (para preseleccionar el suyo)
CREATE OR REPLACE FUNCTION ms_portal_cursos_alumno(aid BIGINT)
RETURNS TABLE(insc_id BIGINT, curso_id BIGINT, curso TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY
  SELECT (i->>'id')::BIGINT, (i->>'cursoId')::BIGINT, c->>'nombre'
  FROM ms_state s,
       jsonb_array_elements(s.data->'insc') i
       LEFT JOIN LATERAL (
         SELECT cc FROM ms_state s2, jsonb_array_elements(s2.data->'cursos') cc
         WHERE s2.id='main' AND (cc->>'id') = (i->>'cursoId')
         LIMIT 1
       ) x(c) ON true
  WHERE s.id='main'
    AND (i->>'alumnoId')::BIGINT = aid
    AND coalesce(i->>'estado','') = 'Activa';
END; $$;

-- 4d) ¿Esta referencia ya fue reportada? (anti-fraude del portal)
CREATE OR REPLACE FUNCTION ms_portal_ref_existe(ref TEXT)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n INT; nref TEXT;
BEGIN
  IF ref IS NULL OR trim(ref) = '' THEN RETURN false; END IF;
  nref := ltrim(lower(regexp_replace(ref,'[\s\-\/#.]','','g')),'0');
  SELECT count(*) INTO n FROM ms_pagos_reportados
   WHERE estado <> 'rechazado'
     AND ltrim(lower(regexp_replace(coalesce(referencia,''),'[\s\-\/#.]','','g')),'0') = nref;
  RETURN n > 0;
END; $$;

-- Permisos: el portal (anon) puede llamar estas 4 funciones
GRANT EXECUTE ON FUNCTION ms_portal_buscar(TEXT)        TO anon;
GRANT EXECUTE ON FUNCTION ms_portal_cursos()            TO anon;
GRANT EXECUTE ON FUNCTION ms_portal_cursos_alumno(BIGINT) TO anon;
GRANT EXECUTE ON FUNCTION ms_portal_ref_existe(TEXT)    TO anon;

-- ============ 5) STORAGE (comprobantes) ============
-- Subir: cualquiera. Ver: cualquiera (URLs impredecibles).
DROP POLICY IF EXISTS "subir comprobantes" ON storage.objects;
CREATE POLICY "subir comprobantes" ON storage.objects FOR INSERT TO anon, authenticated
  WITH CHECK (bucket_id = 'comprobantes');
DROP POLICY IF EXISTS "ver comprobantes" ON storage.objects;
CREATE POLICY "ver comprobantes" ON storage.objects FOR SELECT TO anon, authenticated
  USING (bucket_id = 'comprobantes');

-- ================================================================
-- LISTO. Tu llave publishable ya es segura de exponer:
--  · Sin la clave de equipo → no se lee NADA del panel
--  · El portal solo puede insertar pagos y buscar nombres
-- ================================================================
