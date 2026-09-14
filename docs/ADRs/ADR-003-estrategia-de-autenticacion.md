---
tags: [tfg, adr, seguridad, autenticacion]
adr: 003
estado: "Propuesta"
fecha-decision: null
abierto-desde: 2026-09-14
---

# ADR-003 · Estrategia de autenticación

> **Estado: Propuesta.** El problema está planteado y las opciones identificadas, pero la
> decisión no está tomada. Se cierra en la fase de seguridad del roadmap, cuando exista al
> menos un endpoint de escritura con el que validar el circuito.

## Contexto

El modelo de acceso de DuelVault es inusualmente simple, y conviene no diseñar para un
problema que no se tiene:

- **Un único administrador.** La tabla `app_users` tiene el rol fijado a `ADMIN` con un
  `CHECK`, y no hay registro de usuarios ni recuperación de contraseña en el alcance.
- **Vista pública anónima y de solo lectura.** La mayor parte del tráfico no está
  autenticado.
- **No hay plataforma multiusuario** ni terceros registrando su colección. Eso está
  explícitamente fuera de alcance.
- El escaneo se hace desde el navegador del móvil con `getUserMedia`, lo que **exige
  HTTPS** en el despliegue. Esto condiciona lo que es posible con cookies.

Dos requisitos ya identificados en `07-Casos-limite §C`, que la decisión tiene que
contemplar:

- Un visitante anónimo que llame a un endpoint de administración debe recibir 401 o 403,
  **nunca 500 ni datos parciales**.
- El caso del token que caduca con un formulario largo a medio rellenar. Es la forma más
  rápida de que el usuario odie la aplicación, y no se resuelve solo eligiendo el
  mecanismo: hace falta decidir qué hace el frontend.

## Opciones sobre la mesa

**JWT sin estado.** Es lo que el `00` daba por supuesto y lo que se espera en un portfolio.
Encaja con un backend sin sesión y con un frontend SPA. A cambio hay que decidir dónde lo
guarda Angular (memoria, `localStorage` o cookie), cómo se renueva y cómo se revoca, que es
justo lo que un token sin estado no permite hacer bien.

**Sesión con cookie `HttpOnly` + `Secure` + `SameSite`.** Menos moderno de nombre, pero
para un único administrador y un backend monolítico puede ser más simple y más seguro: el
navegador gestiona la caducidad, el token no es accesible desde JavaScript y la revocación
es inmediata. Exige protección CSRF, que Spring Security ya trae.

## Lo que falta por saber antes de decidir

**Si el frontend se sirve desde el mismo origen que la API.** Si Docker Compose acaba
sirviendo Angular detrás del mismo proxy que el backend, la cookie de sesión es
prácticamente gratis y no hay CORS. Si el frontend se despliega aparte, la cookie
entre orígenes se complica y el JWT gana peso. Esta pregunta la responde la fase de
despliegue, no esta.

## Consecuencias previsibles, sea cual sea la elección

- HTTPS es obligatorio de todas formas, por el escaneo.
- Hace falta un manejador de errores que devuelva 401/403 con el formato de error acordado,
  y un test que lo verifique.
- El caso del formulario a medio rellenar necesita respuesta del lado del frontend
  (guardar borrador, avisar antes de caducar o renovar en silencio), y esa decisión es
  independiente del mecanismo elegido aquí.
