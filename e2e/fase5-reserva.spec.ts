import { test, expect, Page } from '@playwright/test';
import { goToHash, goToLogin, login, openSitterProfile, pins, seen, tab, typeInto } from './helpers';

const btn = (page: Page, name: string | RegExp) =>
  page.getByRole('button', { name, exact: typeof name === 'string' });

async function startBooking(page: Page, sitter: string) {
  await openSitterProfile(page, sitter);
  await btn(page, 'Reservar').click();
  await expect(btn(page, 'Confirmar reserva')).toBeVisible();
}

/**
 * Elige día y hora. Al elegir el día aparece la sección de horas y la pantalla
 * se reacomoda; se confirma que la hora quedó elegida viendo el total.
 */
async function pickWhen(page: Page, day = 'Mañana', hour = '9:00') {
  await btn(page, day).click();
  await expect(async () => {
    await btn(page, hour).click();
    await expect(seen(page, /Total \$[\d.]+/)).toBeVisible({ timeout: 1_500 });
  }).toPass({ timeout: 20_000 });
}

test.describe('perfil del cuidador', () => {
  test('muestra foto, bio, servicios con precio, reseñas y Reservar', async ({ page }) => {
    await openSitterProfile(page, 'Laura Gómez');
    await expect(seen(page, 'Laura Gómez')).toBeVisible();
    await expect(seen(page, /Veterinaria de profesión/)).toBeVisible();
    await expect(seen(page, 'Paseo, $25.000 por paseo')).toBeVisible();
    await expect(seen(page, 'Guardería de día, $60.000 por día')).toBeVisible();
    await expect(seen(page, 'Reseñas (23)')).toBeVisible();
    await expect(seen(page, /^Reseña de Marcela D\., 5 de 5/)).toBeVisible();
    await expect(btn(page, 'Reservar')).toBeVisible();
  });

  test('un cuidador nuevo sin reseñas lo indica', async ({ page }) => {
    await openSitterProfile(page, 'Felipe Cárdenas');
    await expect(seen(page, /Aún no tiene reseñas/)).toBeVisible();
  });

  test('volver atrás regresa al mapa', async ({ page }) => {
    await openSitterProfile(page, 'Laura Gómez');
    await btn(page, 'Back').click();
    await expect(pins(page).first()).toBeAttached();
  });

  test('un cuidador en revisión no tiene perfil público', async ({ page }) => {
    await openSitterProfile(page, 'Laura Gómez');
    await goToHash(page, '#/sitter/a1000000-0000-4000-8000-000000000011');
    await expect(seen(page, 'Este cuidador ya no está disponible.')).toBeVisible();
    await expect(btn(page, 'Reservar')).toHaveCount(0);
  });
});

test.describe('reservar', () => {
  // Flujos largos (registro, reserva y vuelta): más margen cuando corre todo en paralelo.
  test.describe.configure({ timeout: 60_000 });

  test('paseo: elegir todo, ver el total y confirmar', async ({ page }) => {
    await startBooking(page, 'Laura Gómez');
    await expect(btn(page, 'Confirmar reserva')).toBeDisabled();

    await btn(page, 'Paseo · $25.000').click();
    await expect(btn(page, '60 min')).toHaveAttribute('aria-selected', 'true').catch(async () => {
      await btn(page, '60 min').click();
    });
    await btn(page, 'Rocky').click();
    await pickWhen(page);

    await expect(seen(page, 'Total $25.000')).toBeVisible();
    await expect(seen(page, '1 paseo × $25.000')).toBeVisible();
    await expect(btn(page, 'Confirmar reserva')).toBeEnabled();
    await btn(page, 'Confirmar reserva').click();

    await expect(seen(page, '¡Solicitud enviada!')).toBeVisible();
    await expect(seen(page, 'Estado: Pendiente')).toBeVisible();
    await btn(page, 'Volver al mapa').click();
    await expect(pins(page).first()).toBeAttached();
  });

  test('hospedaje de 3 noches: el total multiplica por noche', async ({ page }) => {
    await startBooking(page, 'Andrés Rojas');
    await btn(page, 'Hospedaje nocturno · $85.000').click();
    await btn(page, 'Más noches').click();
    await btn(page, 'Más noches').click();
    await expect(seen(page, '3 noches')).toBeVisible();
    await btn(page, 'Luna').click();
    await pickWhen(page, 'Mañana', '10:00');
    await expect(seen(page, '3 noches × $85.000')).toBeVisible();
    await expect(seen(page, 'Total $255.000')).toBeVisible();
    await btn(page, 'Confirmar reserva').click();
    await expect(seen(page, '¡Solicitud enviada!')).toBeVisible();
  });

  test('guardería de 2 días', async ({ page }) => {
    await startBooking(page, 'Laura Gómez');
    await btn(page, 'Guardería de día · $60.000').click();
    await btn(page, 'Más días').click();
    await btn(page, 'Rocky').click();
    await pickWhen(page);
    await expect(seen(page, 'Total $120.000')).toBeVisible();
  });

  test('las horas que ya pasaron hoy no se pueden elegir', async ({ page }) => {
    await startBooking(page, 'Laura Gómez');
    await btn(page, 'Hoy').click();
    const now = new Date();
    if (now.getHours() >= 7) await expect(btn(page, '7:00')).toBeDisabled();
    if (now.getHours() < 19) await expect(btn(page, '19:00')).toBeEnabled();
    await btn(page, 'Mañana').click();
    await expect(btn(page, '7:00')).toBeEnabled();
  });

  test('un dueño nuevo sin perros lo agrega desde la reserva', async ({ page }) => {
    await goToLogin(page);
    await btn(page, 'Crear cuenta').click();
    await typeInto(page, 'Nombre completo', 'Dueña Nueva');
    await typeInto(page, 'Correo', 'duena.nueva@test.com');
    await typeInto(page, 'Contraseña', 'secreto1');
    await page.getByRole('checkbox').click();
    await page.getByRole('button', { name: 'Crear cuenta' }).last().click();
    await expect(tab(page, 'Explorar')).toBeVisible();

    await page.getByRole('button', { name: /^Cuidador Laura Gómez, / }).dispatchEvent('click');
    await btn(page, 'Ver perfil').click();
    await btn(page, 'Reservar').click();
    await btn(page, 'Paseo · $25.000').click();
    await btn(page, 'Agregar mi perro').click();
    // Espera a que termine la animación del diálogo: un toque antes de tiempo
    // cae fuera de él y lo cierra.
    await expect(page.getByRole('alertdialog')).toBeVisible();
    await page.waitForTimeout(400);
    await typeInto(page, 'Nombre del perro', 'Toby');
    await btn(page, 'Pequeño').click();
    await btn(page, 'Guardar').click();
    await expect(btn(page, 'Toby')).toBeVisible();
    await pickWhen(page);
    await btn(page, 'Confirmar reserva').click();
    await expect(seen(page, '¡Solicitud enviada!')).toBeVisible();
    await expect(seen(page, 'Paseo · Toby')).toBeVisible();
  });

  test('con una reserva activa no se puede cambiar de rol', async ({ page }) => {
    await startBooking(page, 'Laura Gómez');
    await btn(page, 'Paseo · $25.000').click();
    await btn(page, 'Rocky').click();
    await pickWhen(page);
    await btn(page, 'Confirmar reserva').click();
    await btn(page, 'Volver al mapa').click();
    await tab(page, 'Perfil').click();
    await btn(page, 'Cambiar a cuidador').click();
    await expect(seen(page, 'No puedes cambiar de rol mientras tengas reservas activas.')).toBeVisible();
  });

  test('un cuidador no puede abrir la pantalla de reserva', async ({ page }) => {
    await goToLogin(page);
    await login(page, 'cuidador@doggo.app');
    await expect(tab(page, 'Solicitudes')).toBeVisible();
    await goToHash(page, '#/sitter/a1000000-0000-4000-8000-000000000001/book');
    await expect(tab(page, 'Solicitudes')).toBeVisible();
    await expect(btn(page, 'Confirmar reserva')).toHaveCount(0);
  });
});
