# Taller

Gestión de órdenes de trabajo para talleres mecánicos. Funciona solo con dos servicios gratuitos:

- **GitHub Pages** publica la aplicación.
- **Supabase** guarda los datos y los usuarios.

No necesitas servidor propio.

## Qué hace

**Administrador**
- Registra el taller y crea, edita o desactiva mecánicos.
- Crea órdenes con los datos del coche, el tipo de revisión, un checklist básico o completo y la lista de reparaciones con minutos y mecánicos.
- Cada coche aparece dibujado según su carrocería y color.
- Es el único que puede modificar un checklist hecho. Se guardan la fecha y hora de realización y la de modificación, con quién hizo cada una.
- Cierra, cancela o reabre órdenes y consulta el histórico con descarga en CSV.

**Mecánico**
- Solo ve los coches que tiene asignados.
- Debe hacer el checklist antes de empezar. Al guardarlo queda fechado y ya no puede editarlo.
- Cada tarea tiene una cuenta atrás sin pausa. Solo puede **finalizarla**, aunque sea antes de tiempo, o marcar **fin de turno** para dejarla a medias. En ese caso elige quién la continúa y deja una nota, y el siguiente recibe el tiempo restante.
- Si varios mecánicos trabajan a la vez en una tarea, comparten el mismo contador.

Estas reglas están dentro de la base de datos, así que no se pueden saltar manipulando la página. Cada taller registrado solo ve sus propios datos.

## Archivos

| Archivo | Para qué sirve |
|---|---|
| `index.html` | La aplicación |
| `config.js` | Datos de conexión con tu Supabase |
| `supabase.sql` | Crea la base de datos (se usa una vez) |
| `README.md` | Esta guía |

---

## Paso 1: crear la base de datos en Supabase

1. Entra en **supabase.com**, crea una cuenta y pulsa **New project**. Ponle nombre, elige una contraseña para la base de datos (guárdala) y la región más cercana (por ejemplo, Europa).
2. Cuando el proyecto esté listo, ve a **SQL Editor** en el menú de la izquierda y pulsa **New query**.
3. Abre `supabase.sql` con el Bloc de notas, copia todo el contenido, pégalo y pulsa **Run**. Debe aparecer *Success*.
4. Ve a **Authentication → Sign In / Providers** y abre **Email**:
   - Desactiva **Confirm email**. Los mecánicos entran con un nombre de usuario, no con un correo real, así que no pueden confirmar nada.
   - Deja activado **Allow new users to sign up**. La app lo necesita para crear mecánicos.
   - Pulsa **Save**.
5. Ve a **Project Settings → API Keys** (en algunos paneles aparece como **Data API** o **API**) y copia:
   - La **Project URL**, del tipo `https://abcd1234.supabase.co`.
   - La clave **anon** o **publishable**. Nunca uses la clave `service_role` ni la `secret`.

## Paso 2: poner tus datos en config.js

Abre `config.js` con el Bloc de notas y sustituye los dos valores:

```js
window.TALLER_CONFIG = {
  SUPABASE_URL: 'https://abcd1234.supabase.co',
  SUPABASE_ANON_KEY: 'eyJhbGciOi...',
  DOMINIO_USUARIOS: 'taller.app',
};
```

Guarda el archivo. La clave anon es pública por diseño y puede estar en GitHub sin problema: la seguridad la ponen las reglas de la base de datos.

## Paso 3: subirlo a GitHub

1. Entra en **github.com** y crea una cuenta si no la tienes.
2. Pulsa **+** (arriba a la derecha) → **New repository**.
   - Nombre: por ejemplo `taller`.
   - Marca **Public**. GitHub Pages solo es gratis con repositorios públicos. Esto no expone datos: el código es solo la interfaz y los datos están protegidos en Supabase.
   - Pulsa **Create repository**.
3. En la página del repositorio, pulsa el enlace **uploading an existing file**, o **Add file → Upload files**.
4. Arrastra los cuatro archivos: `index.html`, `config.js`, `supabase.sql` y `README.md`. Tienen que quedar sueltos, no dentro de una carpeta.
5. Abajo, pulsa **Commit changes**.

## Paso 4: publicarlo con GitHub Pages

1. En el repositorio, ve a **Settings → Pages**.
2. En **Source** elige **Deploy from a branch**.
3. En **Branch** elige `main` y la carpeta `/ (root)`. Pulsa **Save**.
4. Espera uno o dos minutos y recarga la página. Arriba aparecerá la dirección de tu app, algo como:
   `https://tuusuario.github.io/taller/`

## Paso 5: empezar a usarla

1. Abre la dirección y pulsa **Registrar un taller nuevo**. Pon el nombre del taller, tu nombre, un usuario y una contraseña. Serás el administrador.
2. En **Mecánicos**, crea a tus mecánicos con su usuario y contraseña, y pásaselos.
3. En **Nueva orden**, da de alta el primer coche y sus reparaciones.

**Cierra el registro** cuando hayas creado tu taller, para que nadie más pueda registrar uno en tu base de datos. En Supabase → **SQL Editor**, ejecuta:

```sql
update ajustes set registro_abierto = false;
```

Para volver a abrirlo, cambia `false` por `true`.

## Hacer cambios más adelante

Para modificar un archivo, ábrelo en GitHub, pulsa el lápiz, edita y pulsa **Commit changes**. La web se actualiza sola en un par de minutos.

Si alguna vez te paso una versión nueva de `supabase.sql`, vuelve a ejecutarla en el SQL Editor. No borra datos.

---

## Cosas a tener en cuenta

- **Pausa por inactividad.** Supabase pausa los proyectos gratuitos si pasan varios días sin uso. Si ocurre, entra en su panel y pulsa **Restore project**. Con uso diario no pasa.
- **Copias de seguridad.** Descarga el CSV del histórico de vez en cuando. En Supabase también puedes exportar cualquier tabla desde **Table Editor → Export to CSV**.
- **Nombres de usuario.** No se pueden cambiar después de crearlos. Si hace falta, desactiva el mecánico y crea uno nuevo.
- **Borrar un usuario del todo.** Se hace desde Supabase → **Authentication → Users**. Solo es posible si nunca tuvo tareas asignadas. Si ya tiene historial, desactívalo desde la app.
- **Contraseña olvidada.** El administrador puede poner una nueva a cualquier mecánico desde **Mecánicos → Editar**. Si el administrador olvida la suya, cámbiala en Supabase → **Authentication → Users**, en el menú del usuario.

## Si algo falla

| Mensaje | Solución |
|---|---|
| *Falta configurar* | Revisa que `config.js` tenga tu URL y tu clave |
| *Falta desactivar "Confirm email"* | Paso 1, punto 4 |
| *Falta activar el registro de usuarios* | Activa **Allow new users to sign up** (paso 1, punto 4) |
| *Usuario no válido* al crear usuarios | Cambia `DOMINIO_USUARIOS` en `config.js`, por ejemplo por `mitaller.com`. Hazlo antes de crear usuarios: los ya creados dejarían de poder entrar |
| *Ese usuario ya existe* al registrarte | Ya se creó en un intento anterior. Bórralo en **Authentication → Users** y repite |
| *El registro de talleres está cerrado* | Es lo esperado tras cerrarlo. Ábrelo con el SQL del paso 5 si lo necesitas |
| Página en blanco o 404 en GitHub | Comprueba que `index.html` está en la raíz del repositorio y espera unos minutos |
