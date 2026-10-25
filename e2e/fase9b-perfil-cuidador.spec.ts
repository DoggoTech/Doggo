import { test, expect, Page } from '@playwright/test';
import {
  btn, enterAsOwner, goToLogin, openProfileFromMap, scrollToEnd, seen, switchDemo, tab, typeInto, zoneMap, zonePin,
} from './helpers';

test.describe.configure({ timeout: 90_000 });

const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  'base64',
);

async function registerSitter(page: Page, name: string, email: string) {
  await goToLogin(page);
  await btn(page, 'Crear cuenta').click();
  await btn(page, 'Soy cuidador').click();
  await typeInto(page, 'Nombre completo', name);
  await typeInto(page, 'Correo', email);
  await typeInto(page, 'Contraseña', 'secreto1');
  await page.getByRole('checkbox').click();
  await page.getByRole('button', { name: 'Crear cuenta' }).last().click();
  await expect(seen(page, 'Tu perfil está en revisión')).toBeVisible();
}

async function pickPhoto(page: Page, file: { name: string; mimeType: string; buffer: Buffer }) {
  const chooser = page.waitForEvent('filechooser');
  await btn(page, 'Cambiar foto').click();
  await (await chooser).setFiles(file);
}

test.describe('zona de servicio', () => {
  test.describe('con GPS', () => {
    test.use({ geolocation: { latitude: 4.74, longitude: -74.09 }, permissions: ['geolocation'] }); // Suba

    test('el cuidador cambia su zona con su ubicación actual; el dueño ve barrio y radio', async ({ page }) => {
      await enterAsOwner(page);
      await switchDemo(page, 'Cuidador');
      await tab(page, 'Servicios').click();
      await scrollToEnd(page, btn(page, 'Guardar zona'));
      await btn(page, 'Usar mi ubicación actual').click();
      await expect(zonePin(page)).toBeAttached();
      await typeInto(page, 'Barrio', 'Suba');
      for (let i = 0; i < 3; i++) await btn(page, 'Más radio').click();
      await expect(seen(page, 'Radio: 8 km')).toBeVisible();
      await btn(page, 'Guardar zona').click();
      await expect(seen(page, 'Zona guardada')).toBeVisible();

      await switchDemo(page, 'Dueño');
      await openProfileFromMap(page, 'Carlos Cuidador');
      await expect(seen(page, 'Suba · atiende a 8 km a la redonda')).toBeVisible();
    });
  });

  test('un cuidador nuevo marca su zona tocando el mapa', async ({ page }) => {
    await registerSitter(page, 'Cuidadora Mapa', 'cuidadora.mapa@test.com');
    await tab(page, 'Servicios').click();
    await expect(seen(page, /^Aún no defines tu zona/)).toBeVisible(); // aviso arriba
    await scrollToEnd(page, btn(page, 'Guardar zona'));

    await btn(page, 'Guardar zona').click();
    await expect(seen(page, /Marca tu ubicación en el mapa/)).toBeVisible();

    const map = await zoneMap(page).boundingBox();
    await page.mouse.click(map!.x + map!.width / 2, map!.y + map!.height / 2);
    await expect(zonePin(page)).toBeAttached();

    await btn(page, 'Guardar zona').click();
    await expect(seen(page, /Escribe tu barrio/)).toBeVisible();

    await typeInto(page, 'Barrio', 'Teusaquillo');
    await btn(page, 'Guardar zona').click();
    await expect(seen(page, 'Zona guardada')).toBeVisible();
    await expect(seen(page, /^Aún no defines tu zona/)).toHaveCount(0);
  });

  test('el admin ve si un cuidador en revisión aún no tiene zona', async ({ page }) => {
    await registerSitter(page, 'Cuidador Incompleto', 'incompleto@test.com');
    await switchDemo(page, 'Administrador');
    await expect(seen(page, /^Cuidador Incompleto/)).toBeVisible();
    await expect(seen(page, /Aún no define su zona de servicio/)).toBeVisible();
    await expect(seen(page, /Zona: Bosa, 5 km/)).toBeVisible(); // Natalia sí la tiene
  });
});

test.describe('foto de perfil', () => {
  test('el cuidador sube su foto y el dueño la ve', async ({ page }) => {
    await enterAsOwner(page);
    await switchDemo(page, 'Cuidador');
    await tab(page, 'Perfil').click();
    await pickPhoto(page, { name: 'carlos.png', mimeType: 'image/png', buffer: PNG });
    await expect(seen(page, 'Foto actualizada')).toBeVisible();

    await switchDemo(page, 'Dueño');
    await openProfileFromMap(page, 'Carlos Cuidador');
    await expect(page.getByLabel('Foto de Carlos Cuidador').first()).toBeAttached();
  });

  test('un archivo que no es imagen se rechaza', async ({ page }) => {
    await enterAsOwner(page);
    await switchDemo(page, 'Cuidador');
    await tab(page, 'Perfil').click();
    await pickPhoto(page, { name: 'documento.pdf', mimeType: 'application/pdf', buffer: Buffer.from('%PDF-1.4') });
    await expect(seen(page, 'La foto debe ser JPG, PNG o WEBP.')).toBeVisible();
  });
});
