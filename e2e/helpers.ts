import { expect, Page } from '@playwright/test';

/** Abre la app y espera a que Flutter exponga el árbol de accesibilidad. */
export async function openApp(page: Page, path = '/') {
  await page.goto(path);
  await expect(page.locator('flutter-view')).toBeAttached({ timeout: 20_000 });
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
