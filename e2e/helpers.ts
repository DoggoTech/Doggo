import { expect, Locator, Page } from '@playwright/test';

// PNG transparente de 1x1: reemplaza los tiles del mapa y las fotos externas
// para que las pruebas no dependan de la red ni de terceros.
const BLANK_PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  'base64',
);

async function mockExternalImages(page: Page) {
  await page.route(/tile\.openstreetmap\.org/, (route) =>
    route.fulfill({ contentType: 'image/png', body: BLANK_PNG }),
  );
  // Las fotos fallan a propósito: así la app muestra la inicial del cuidador.
  await page.route(/i\.pravatar\.cc/, (route) => route.fulfill({ status: 404 }));
}

/**
 * Abre la app. Por defecto activa la accesibilidad de Flutter pulsando su botón
 * nativo (como hace un lector de pantalla) para poder localizar elementos por
 * etiqueta. Con `semantics: false` queda el canvas "puro", igual que para un
 * usuario normal con mouse.
 */
export async function openApp(page: Page, path = '/', { semantics = true } = {}) {
  await mockExternalImages(page);
  await page.goto(path);
  await expect(page.locator('flutter-view')).toBeAttached({ timeout: 20_000 });
  if (semantics) await enableSemantics(page);
}

export async function enableSemantics(page: Page) {
  // Flutter muestra su botón nativo de accesibilidad; si la app ya la tuviera
  // activa por defecto, ese botón no existe y no hay nada que pulsar.
  const entry = page.locator('flt-semantics-placeholder, flt-semantics').first();
  await entry.waitFor({ state: 'attached', timeout: 20_000 });
  if ((await entry.evaluate((el) => el.tagName)).toLowerCase() === 'flt-semantics-placeholder') {
    await entry.evaluate((el) => (el as HTMLElement).click());
  }
  await expect(page.locator('flt-semantics').first()).toBeAttached({ timeout: 10_000 });
}

/** Salta splash y onboarding y deja la app en la pantalla de login. */
export async function goToLogin(page: Page) {
  await openApp(page);
  await page.getByRole('button', { name: 'Saltar' }).click({ timeout: 15_000 });
  await expect(page.getByText('Iniciar sesión')).toBeVisible();
}

/**
 * Escribe en un campo de Flutter. Flutter tarda un instante en enfocar el
 * input y pierde las primeras teclas, así que se verifica el valor y se
 * reintenta hasta que quede exacto.
 */
export async function typeInto(page: Page, label: string, text: string) {
  const box = page.getByRole('textbox', { name: label });
  await expect(async () => {
    await box.click();
    await expect(box).toBeFocused({ timeout: 1_000 });
    await page.waitForTimeout(150);
    await box.press('ControlOrMeta+a');
    await box.press('Backspace');
    await box.pressSequentially(text);
    await expect(box).toHaveValue(text, { timeout: 1_000 });
  }).toPass({ timeout: 15_000 });
}

export async function login(page: Page, email: string, password = 'doggo123') {
  await typeInto(page, 'Correo', email);
  await typeInto(page, 'Contraseña', password);
  await page.getByRole('button', { name: 'Entrar' }).click();
}

/** Los avisos con liveRegion aparecen duplicados en el árbol: tomamos el primero. */
export const texto = (page: Page, t: string | RegExp) => page.getByText(t).first();

/**
 * Destino de navegación. En celular (barra inferior) Flutter lo expone como
 * `tab`; en escritorio (riel lateral) como botón "Nombre Tab N of M".
 */
export const tab = (page: Page, name: string) =>
  page
    .getByRole('tab', { name, exact: true })
    .or(page.getByRole('button', { name: new RegExp(`^${name} Tab \\d+ of \\d+$`) }));

/** Entra con "Probar demo" (dueño) y espera a que carguen los pines del mapa. */
export async function enterAsOwner(page: Page) {
  await goToLogin(page);
  await page.getByRole('button', { name: 'Probar demo' }).click();
  await expect(pins(page).first()).toBeAttached({ timeout: 15_000 });
}

/** Pines del mapa: "Cuidador <nombre>, $<precio>". */
export const pins = (page: Page) =>
  page.getByRole('button', { name: /^Cuidador .+, \$[\d.]+$/ });

export const pin = (page: Page, name: string) =>
  page.getByRole('button', { name: new RegExp(`^Cuidador ${name}, `) });

/** Tarjetas de la lista: "<nombre>, <barrio>, a <distancia>, <precio> <unidad>". */
export const tiles = (page: Page) =>
  page.getByRole('button', { name: /, a [\d,]+ (km|m), \$[\d.]+ / });

/**
 * Pulsa un chip de servicio. La barra de filtros se desplaza horizontalmente y
 * Flutter solo construye lo visible, así que se desplaza hasta que aparezca.
 */
export async function selectService(page: Page, name: string) {
  const chip = page.getByRole('button', { name, exact: true });
  const anchor = await page.getByRole('button', { name: 'Todos' }).boundingBox();
  for (let i = 0; i < 8 && (await chip.count()) === 0; i++) {
    await page.mouse.move(anchor!.x + anchor!.width / 2, anchor!.y + anchor!.height / 2);
    await page.mouse.wheel(300, 0);
    await page.waitForTimeout(200);
  }
  await chip.click();
}

/** Entra como dueño demo y abre el perfil de un cuidador por su pin. */
export async function openSitterProfile(page: Page, name: string) {
  await enterAsOwner(page);
  await openProfileFromMap(page, name);
}

/**
 * Con la app ya abierta en el mapa, abre el perfil de un cuidador. No recarga
 * la página: en el modo demo recargar borra todo lo hecho.
 */
export async function openProfileFromMap(page: Page, name: string) {
  await expect(pin(page, name)).toBeAttached({ timeout: 15_000 });
  await pin(page, name).dispatchEvent('click');
  await page.getByRole('button', { name: 'Ver perfil' }).click();
  await expect(page.getByText('Perfil del cuidador')).toBeVisible();
}

/** Navega dentro de la app sin recargar (se conserva la sesión en memoria). */
export async function goToHash(page: Page, route: string) {
  await page.evaluate((r) => (window.location.hash = r), route);
}

/**
 * Un texto que se ve en pantalla. Flutter lo expone como texto o como etiqueta
 * (aria-label) del grupo que lo contiene según la estructura; da igual cuál.
 */
export const seen = (page: Page, t: string | RegExp) => page.getByText(t).or(page.getByLabel(t)).first();

// ---- Hoja de reserva ----
export const btn = (page: Page, name: string | RegExp) =>
  page.getByRole('button', { name, exact: typeof name === 'string' });

export async function openSheet(page: Page, sitter: string) {
  await enterAsOwner(page);
  await openSheetFromMap(page, sitter);
}

/** Con la app ya abierta en el mapa, abre la hoja de reserva de un cuidador. */
export async function openSheetFromMap(page: Page, sitter: string) {
  await openProfileFromMap(page, sitter);
  await btn(page, 'Reservar').click();
  await expect(btn(page, 'Enviar solicitud')).toBeVisible();
}

/** Valor que muestra un selector de la hoja, p. ej. "Día: Mañana". */
export const value = (page: Page, title: string, v: string | RegExp) =>
  typeof v === 'string' ? seen(page, new RegExp(`^${title}: ${v.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`)) : seen(page, v);

export async function readValue(page: Page, title: string) {
  const el = page.getByText(new RegExp(`^${title}: `)).or(page.getByLabel(new RegExp(`^${title}: `))).first();
  const text = (await el.getAttribute('aria-label')) ?? (await el.textContent()) ?? '';
  return text.replace(`${title}: `, '').trim();
}

/**
 * Pulsa un botón −/+ y espera a que cambie el valor que muestra. Devuelve
 * `false` si ya no se puede avanzar (botón inactivo o valor sin cambio).
 * Flutter marca el botón como inactivo un instante después del toque, por eso
 * se mira el valor y no solo el estado del botón.
 */
export async function step(page: Page, title: string, name: string) {
  const b = btn(page, name);
  if (!(await b.isEnabled())) return false;
  const before = await readValue(page, title);
  await b.click({ timeout: 2_000 }).catch(() => {});
  try {
    await expect.poll(() => readValue(page, title), { timeout: 1_500 }).not.toBe(before);
    return true;
  } catch {
    return false;
  }
}

export async function stepToEnd(page: Page, title: string, name: string) {
  for (let i = 0; i < 40 && (await step(page, title, name)); i++);
}

/** Lleva un selector −/+ al mínimo y luego avanza hasta el valor buscado. */
export async function stepTo(page: Page, title: string, target: string, prev: string, next: string) {
  await stepToEnd(page, title, prev);
  for (let i = 0; i < 40; i++) {
    if ((await readValue(page, title)) === target) return;
    if (!(await step(page, title, next))) break;
  }
  expect(await readValue(page, title)).toBe(target);
}

export async function pickWhen(page: Page, day = 'Mañana', hour = '9:00') {
  await stepTo(page, 'Día', day, 'Día anterior', 'Día siguiente');
  await stepTo(page, 'Hora', hour, 'Hora anterior', 'Hora siguiente');
}


/**
 * Cambia de cuenta con el panel "Modo demo" sin perder los datos en memoria, y
 * espera a que cargue la navegación de la cuenta nueva (antes de eso, la app
 * todavía está redirigiendo y una navegación inmediata se perdería).
 */
export async function switchDemo(page: Page, role: 'Dueño' | 'Cuidador' | 'Administrador' | 'Superadministrador') {
  const firstTab = { Dueño: 'Explorar', Cuidador: 'Solicitudes', Administrador: 'Aprobaciones', Superadministrador: 'Aprobaciones' }[role];
  await tab(page, 'Perfil').click();
  const demo = btn(page, `Demo: ${role}`);
  await scrollUntil(page, demo); // el panel demo está al final del perfil
  await demo.dispatchEvent('click');
  await expect(tab(page, firstTab)).toBeVisible();
  await expect(tab(page, 'Perfil')).toBeVisible();
}

/** Desde el mapa del dueño, reserva un paseo con Carlos Cuidador (mañana a las 9:00). */
export async function bookWithCarlos(page: Page) {
  await openSheetFromMap(page, 'Carlos Cuidador');
  await btn(page, 'Rocky').click();
  await pickWhen(page);
  await btn(page, 'Enviar solicitud').click();
  await expect(seen(page, '¡Solicitud enviada!')).toBeVisible();
  await btn(page, 'Volver al mapa').click();
  await expect(pins(page).first()).toBeAttached();
}

/**
 * Desplaza la lista con la rueda hasta que aparezca el elemento (Flutter
 * construye solo lo visible). Alterna el punto donde gira la rueda: si cae
 * sobre un campo de texto de varias líneas, ese campo se queda con el gesto.
 */
export async function scrollUntil(page: Page, target: Locator) {
  const vp = page.viewportSize()!;
  const spots = [
    [vp.width / 2, vp.height / 2],
    [vp.width / 2, vp.height * 0.25],
    [vp.width / 2, vp.height * 0.75],
  ];
  for (let i = 0; i < 18 && (await target.count()) === 0; i++) {
    const [x, y] = spots[i % spots.length];
    await page.mouse.move(x, y);
    await page.mouse.wheel(0, 350);
    await page.waitForTimeout(150);
  }
  await expect(target.first()).toBeAttached();
}

/** Baja hasta el final de una lista larga (p. ej. la zona de servicio, al final de Servicios). */
export async function scrollToEnd(page: Page, lastItem: Locator) {
  await scrollUntil(page, lastItem);
  const vp = page.viewportSize()!;
  for (let i = 0; i < 4; i++) {
    await page.mouse.move(vp.width / 2, vp.height * 0.25);
    await page.mouse.wheel(0, 600);
    await page.waitForTimeout(120);
  }
  await page.waitForTimeout(300);
}

/** El pin que marca la zona dentro del mini mapa (forma parte del botón del mapa). */
export const zonePin = (page: Page) => page.getByRole('button', { name: /Tu zona marcada/ });
export const zoneMap = (page: Page) => page.getByRole('button', { name: /^Mapa para marcar tu zona/ });
