import { test, expect, Page } from '@playwright/test';
import { goToHash, goToLogin, login, openSitterProfile, pins, seen, tab, typeInto } from './helpers';

const btn = (page: Page, name: string | RegExp) =>
  page.getByRole('button', { name, exact: typeof name === 'string' });

async function openSheet(page: Page, sitter: string) {
  await openSitterProfile(page, sitter);
  await btn(page, 'Reservar').click();
  await expect(btn(page, 'Enviar solicitud')).toBeVisible();
}

/** Valor que muestra un selector de la hoja, p. ej. "Día: Mañana". */
const value = (page: Page, title: string, v: string | RegExp) =>
  typeof v === 'string' ? seen(page, new RegExp(`^${title}: ${v.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`)) : seen(page, v);

async function readValue(page: Page, title: string) {
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
async function step(page: Page, title: string, name: string) {
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

async function stepToEnd(page: Page, title: string, name: string) {
  for (let i = 0; i < 40 && (await step(page, title, name)); i++);
}

/** Lleva un selector −/+ al mínimo y luego avanza hasta el valor buscado. */
async function stepTo(page: Page, title: string, target: string, prev: string, next: string) {
  await stepToEnd(page, title, prev);
  for (let i = 0; i < 40; i++) {
    if ((await readValue(page, title)) === target) return;
    if (!(await step(page, title, next))) break;
  }
  expect(await readValue(page, title)).toBe(target);
}

async function pickWhen(page: Page, day = 'Mañana', hour = '9:00') {
  await stepTo(page, 'Día', day, 'Día anterior', 'Día siguiente');
  await stepTo(page, 'Hora', hour, 'Hora anterior', 'Hora siguiente');
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

test.describe('reservar (hoja compacta)', () => {
  // Flujos largos (registro, reserva y vuelta): más margen cuando corre todo en paralelo.
  test.describe.configure({ timeout: 60_000 });

  test('paseo: elegir perro, día y hora, ver el total y enviar', async ({ page }) => {
    await openSheet(page, 'Laura Gómez');
    await expect(value(page, 'Duración', '60 min')).toBeVisible(); // paseo por defecto
    await expect(btn(page, 'Enviar solicitud')).toBeDisabled(); // falta el perro (tiene dos)

    await btn(page, 'Rocky').click();
    await pickWhen(page);
    await expect(seen(page, 'Total $25.000')).toBeVisible();
    await expect(seen(page, /^1 paseo × \$25\.000/)).toBeVisible();
    await expect(seen(page, /^Laura tiene hasta .+ para responder\.$/)).toBeVisible();

    await btn(page, 'Enviar solicitud').click();
    await expect(seen(page, '¡Solicitud enviada!')).toBeVisible();
    await expect(seen(page, 'Estado: Pendiente')).toBeVisible();
    await btn(page, 'Volver al mapa').click();
    await expect(pins(page).first()).toBeAttached();
  });

  test('hospedaje de 3 noches con + y −: el total multiplica por noche', async ({ page }) => {
    await openSheet(page, 'Andrés Rojas');
    await btn(page, 'Hospedaje nocturno · $85.000').click();
    await btn(page, 'Más noches').click();
    await btn(page, 'Más noches').click();
    await btn(page, 'Más noches').click();
    await btn(page, 'Menos noches').click();
    await expect(value(page, 'Noches', '3 noches')).toBeVisible();
    await btn(page, 'Luna').click();
    await pickWhen(page, 'Mañana', '10:00');
    await expect(seen(page, /^3 noches × \$85\.000/)).toBeVisible();
    await expect(seen(page, 'Total $255.000')).toBeVisible();
    await btn(page, 'Enviar solicitud').click();
    await expect(seen(page, '¡Solicitud enviada!')).toBeVisible();
  });

  test('guardería de 2 días', async ({ page }) => {
    await openSheet(page, 'Laura Gómez');
    await btn(page, 'Guardería de día · $60.000').click();
    await btn(page, 'Más días').click();
    await btn(page, 'Rocky').click();
    await expect(seen(page, 'Total $120.000')).toBeVisible();
  });

  test('la hora más temprana deja al menos 1 hora para que el cuidador responda', async ({ page }) => {
    await openSheet(page, 'Laura Gómez');
    await stepToEnd(page, 'Día', 'Día anterior');
    await stepToEnd(page, 'Hora', 'Hora anterior');
    const day = await readValue(page, 'Día');
    const [h, m] = (await readValue(page, 'Hora')).split(':').map(Number);
    if (day === 'Hoy') {
      const now = new Date();
      const minutesAhead = h * 60 + m - (now.getHours() * 60 + now.getMinutes());
      expect(minutesAhead).toBeGreaterThanOrEqual(59);
    } else {
      expect(`${h}:${String(m).padStart(2, '0')}`).toBe('7:00'); // primer día disponible empieza a las 7
    }
  });

  test('la franja de horas va de 7:00 a 19:00', async ({ page }) => {
    await openSheet(page, 'Laura Gómez');
    await stepTo(page, 'Día', 'Mañana', 'Día anterior', 'Día siguiente');
    await stepToEnd(page, 'Hora', 'Hora anterior');
    expect(await readValue(page, 'Hora')).toBe('7:00');
    await stepToEnd(page, 'Hora', 'Hora siguiente');
    expect(await readValue(page, 'Hora')).toBe('19:00');
  });

  test('un dueño nuevo sin perros lo agrega desde la hoja y queda elegido', async ({ page }) => {
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
    await btn(page, 'Agregar mi perro').click();
    // Espera a que termine la animación del diálogo: un toque antes de tiempo
    // cae fuera de él y lo cierra.
    await expect(page.getByRole('alertdialog')).toBeVisible();
    await page.waitForTimeout(400);
    await typeInto(page, 'Nombre del perro', 'Toby');
    await btn(page, 'Pequeño').click();
    await btn(page, 'Guardar').click();
    await expect(btn(page, 'Toby')).toBeVisible();
    await expect(btn(page, 'Enviar solicitud')).toBeEnabled(); // su único perro queda elegido
    await pickWhen(page);
    await btn(page, 'Enviar solicitud').click();
    await expect(seen(page, '¡Solicitud enviada!')).toBeVisible();
    await expect(seen(page, 'Paseo · Toby')).toBeVisible();
  });

  test('con una reserva activa no se puede cambiar de rol', async ({ page }) => {
    await openSheet(page, 'Laura Gómez');
    await btn(page, 'Rocky').click();
    await pickWhen(page);
    await btn(page, 'Enviar solicitud').click();
    await btn(page, 'Volver al mapa').click();
    await tab(page, 'Perfil').click();
    await btn(page, 'Cambiar a cuidador').click();
    await expect(seen(page, 'No puedes cambiar de rol mientras tengas reservas activas.')).toBeVisible();
  });

  test('un cuidador ve perfiles pero no puede reservar', async ({ page }) => {
    await goToLogin(page);
    await login(page, 'cuidador@doggo.app');
    await expect(tab(page, 'Solicitudes')).toBeVisible();
    await goToHash(page, '#/sitter/a1000000-0000-4000-8000-000000000001');
    await expect(seen(page, 'Laura Gómez')).toBeVisible();
    await expect(btn(page, 'Reservar')).toHaveCount(0);
  });
});
