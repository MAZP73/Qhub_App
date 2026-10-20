// Registro de un CLIENTE de la app móvil. Solo esta función (service_role) marca la cuenta como cliente:
// app_metadata.tipo_cuenta='cliente' se escribe aquí, HARDCODEADO, nunca desde el cuerpo de la petición (el rol/tipo
// jamás sale de lo que manda el cliente). Si el correo ya existe —sea cliente o staff de la web— se responde "ya registrado"
// sin revelar si es del staff y sin cambiarle el tipo: una cuenta de la web no se convierte en cliente.
import { createClient } from "npm:@supabase/supabase-js@2";
import { parseRegistro } from "../_shared/registro.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "Método no permitido" });

  const p = parseRegistro(await req.json().catch(() => null) as Record<string, unknown> | null);
  if (!p.ok) return json(400, { error: "validation", fields: p.fields });

  const url = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  // ¿Ya existe el correo? (service_role) No se revela si es cliente o staff, y no se le toca el tipo_cuenta.
  const { data: list, error: lookupErr } = await admin.auth.admin.listUsers();
  if (lookupErr) return json(500, { error: "No pudimos completar el registro. Inténtalo de nuevo." });
  const exists = list.users.some((u) => (u.email ?? "").toLowerCase() === p.value.email);
  if (exists) return json(409, { error: "ya_registrado" });

  const { data: created, error } = await admin.auth.admin.createUser({
    email: p.value.email,
    password: p.value.password,
    user_metadata: { nombre: p.value.nombre, apellido: p.value.apellido },
    app_metadata: { tipo_cuenta: "cliente" },   // HARDCODEADO: nunca del cuerpo
  });
  if (error || !created.user) {
    if (error?.status === 429) return json(429, { error: "Hay demasiados intentos. Espera unos minutos." });
    // Carrera: el correo se creó entre la consulta y el alta.
    if ((error?.message ?? "").toLowerCase().includes("already")) return json(409, { error: "ya_registrado" });
    return json(500, { error: "No pudimos completar el registro. Inténtalo de nuevo." });
  }

  // Si el proyecto exige confirmar el correo, createUser deja la cuenta sin confirmar: hay que avisar y mandar el enlace.
  const needsConfirmation = !created.user.email_confirmed_at;
  if (needsConfirmation) {
    await createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!).auth.signInWithOtp({
      email: p.value.email,
      options: { shouldCreateUser: false },
    });
  }
  return json(200, { created: true, needsConfirmation });
});
