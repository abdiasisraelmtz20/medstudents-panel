# MedStudents · Panel + Portal de Pagos

Sistema administrativo de **MedStudents** (Dr. Abdías Martínez · medstudents.page).

| Archivo | Qué es |
|---|---|
| `index.html` | Panel de control (privado, protegido por clave de equipo) |
| `reportar.html` | Portal público donde los alumnos reportan sus pagos |
| `setup_supabase.sql` | Crea las tablas (correr 1 vez) |
| `blindaje_rls.sql` | Seguridad RLS (correr 1 vez, después del anterior) |

## 🔐 Seguridad

Los datos NO viven en estos archivos: viven en Supabase, protegidos por **RLS**.
Sin la **clave de equipo**, el panel no puede leer ni escribir nada — aunque el código sea público.
El portal solo puede **insertar** pagos reportados y buscar nombres (sin ver finanzas).

## 🚀 Setup

1. Supabase → SQL Editor → correr `setup_supabase.sql`, luego `blindaje_rls.sql`
2. En `blindaje_rls.sql` **cambia la clave de equipo** por una tuya
3. Panel → Respaldo → Supabase → pegar URL, Publishable Key y **Clave de equipo** → Conectar
4. GitHub → Settings → Pages → main / (root)

Panel: `https://TU-USUARIO.github.io/medstudents-panel/`
Portal: `https://TU-USUARIO.github.io/medstudents-panel/reportar.html`

En Odoo solo pon un **enlace** al panel, no el código.

## ✨ Funciones

Multiusuario · presencia del equipo · máquina del tiempo (30 días) · reparto Dr. Ayax · cobranza masiva y preventiva · campañas a ex-alumnos · proyección de cierre · validación de pagos con comprobante · **anti-fraude de comprobantes duplicados** · constancias y recibos PDF.
