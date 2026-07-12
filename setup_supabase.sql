-- ================================================================
-- MedStudents Admin Panel · Supabase Setup
-- Dr. Abdías Martínez · medstudents.page
--
-- INSTRUCCIONES:
-- 1. Crea un proyecto en https://supabase.com (Free tier funciona)
-- 2. Ve a SQL Editor y pega TODO este script → Run
-- 3. Ve a Realtime → habilita el proyecto si no está habilitado
-- 4. Copia tu Project URL y Anon Key desde Settings → API
-- 5. En el panel ve a Respaldo → Supabase → pega URL y Anon Key
-- ================================================================

-- Tabla principal de estado compartido
CREATE TABLE IF NOT EXISTS ms_state (
  id        TEXT PRIMARY KEY DEFAULT 'main',
  data      JSONB NOT NULL DEFAULT '{}',
  rev       BIGINT DEFAULT 0,
  updated_by TEXT,
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Tabla de actividad / auditoría de equipo
CREATE TABLE IF NOT EXISTS ms_activity (
  id         BIGSERIAL PRIMARY KEY,
  usuario    TEXT NOT NULL DEFAULT 'Sistema',
  accion     TEXT NOT NULL,
  detalles   TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Tabla de bloqueos temporales (evita edición simultánea de pagos)
CREATE TABLE IF NOT EXISTS ms_locks (
  id         TEXT PRIMARY KEY,  -- ej. 'pago_12345'
  usuario    TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Habilitar realtime en ms_state (lo más importante)
ALTER PUBLICATION supabase_realtime ADD TABLE ms_state;
ALTER PUBLICATION supabase_realtime ADD TABLE ms_activity;

-- Deshabilitar RLS (panel interno, autenticado con PIN)
ALTER TABLE ms_state     DISABLE ROW LEVEL SECURITY;
ALTER TABLE ms_activity  DISABLE ROW LEVEL SECURITY;
ALTER TABLE ms_locks     DISABLE ROW LEVEL SECURITY;

-- Fila inicial vacía
INSERT INTO ms_state (id, data, rev)
  VALUES ('main', '{}', 0)
  ON CONFLICT (id) DO NOTHING;

-- Índice para actividad reciente
CREATE INDEX IF NOT EXISTS ms_activity_created_idx ON ms_activity(created_at DESC);

-- Función para limpiar bloqueos expirados (se llama automáticamente)
CREATE OR REPLACE FUNCTION cleanup_locks()
RETURNS void LANGUAGE sql AS $$
  DELETE FROM ms_locks WHERE expires_at < now();
$$;

-- ================================================================
-- LISTO. Copie el Project URL y Anon Key desde Settings → API
-- ================================================================

-- Máquina del tiempo: snapshots diarios (30 días)
CREATE TABLE IF NOT EXISTS ms_snapshots (
  fecha      DATE PRIMARY KEY,
  data       JSONB NOT NULL,
  rev        BIGINT DEFAULT 0,
  resumen    TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE ms_snapshots DISABLE ROW LEVEL SECURITY;
-- ================================================================
-- MedStudents · Portal "Reportar mi pago" · Supabase Setup
-- Ejecutar en SQL Editor DESPUÉS del setup_supabase.sql principal
-- ================================================================

-- Tabla de reportes de pago hechos por los alumnos
CREATE TABLE IF NOT EXISTS ms_pagos_reportados (
  id           BIGSERIAL PRIMARY KEY,
  alumno_id    BIGINT,               -- id del alumno en el panel (si se identificó)
  insc_id      BIGINT,               -- id de inscripción/curso (si se eligió)
  nombre       TEXT NOT NULL,        -- nombre que escribió el alumno
  email        TEXT,
  whatsapp     TEXT,
  curso        TEXT,                 -- texto del curso elegido
  monto        NUMERIC NOT NULL,
  metodo       TEXT DEFAULT 'Transferencia',
  referencia   TEXT,
  fecha_pago   DATE,
  comprobante  TEXT,                 -- URL de la imagen en Storage
  nota         TEXT,
  estado       TEXT DEFAULT 'pendiente',  -- pendiente | aprobado | rechazado
  revisado_por TEXT,
  motivo_rechazo TEXT,
  created_at   TIMESTAMPTZ DEFAULT now(),
  updated_at   TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ms_pagos_rep_estado_idx ON ms_pagos_reportados(estado, created_at DESC);

-- Realtime para que el panel vea los reportes al instante
ALTER PUBLICATION supabase_realtime ADD TABLE ms_pagos_reportados;

-- El portal usa el Anon Key. Con RLS activado limitamos qué puede hacer:
--  - INSERT: cualquiera puede reportar su pago
--  - SELECT/UPDATE/DELETE: NO permitido con anon (solo el panel via service, o anon con estado)
-- Para simplicidad operativa (panel usa el mismo anon key) dejamos RLS desactivado
-- igual que las demás tablas. El portal solo hace INSERT.
ALTER TABLE ms_pagos_reportados DISABLE ROW LEVEL SECURITY;

-- ================================================================
-- STORAGE: bucket para los comprobantes (capturas de transferencia)
-- ================================================================
INSERT INTO storage.buckets (id, name, public)
  VALUES ('comprobantes', 'comprobantes', true)
  ON CONFLICT (id) DO NOTHING;

-- Política: cualquiera puede subir (INSERT) al bucket comprobantes
DROP POLICY IF EXISTS "subir comprobantes" ON storage.objects;
CREATE POLICY "subir comprobantes" ON storage.objects
  FOR INSERT TO anon, authenticated
  WITH CHECK (bucket_id = 'comprobantes');

-- Política: cualquiera puede ver (los links son públicos, difíciles de adivinar)
DROP POLICY IF EXISTS "ver comprobantes" ON storage.objects;
CREATE POLICY "ver comprobantes" ON storage.objects
  FOR SELECT TO anon, authenticated
  USING (bucket_id = 'comprobantes');

-- ================================================================
-- LISTO. Ahora el portal reportar.html puede recibir pagos.
-- ================================================================
