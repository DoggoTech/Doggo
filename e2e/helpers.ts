import { expect, Page } from '@playwright/test';

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

/** Desde el mapa (como dueño demo), abre el perfil de un cuidador por su pin. */
export async function openSitterProfile(page: Page, name: string) {
  await enterAsOwner(page);
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
