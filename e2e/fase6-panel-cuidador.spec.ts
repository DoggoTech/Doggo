import { test, expect, Page } from '@playwright/test';
import {
  bookWithCarlos, btn, enterAsOwner, goToLogin, openProfileFromMap, openSheetFromMap, pin, readValue,
  scrollUntil, seen, stepTo, stepToEnd, switchDemo, tab, typeInto,
} from './helpers';

/** Hora que muestra "<Día> desde/hasta: H:MM". */
async function timeOf(page: Page, title: string) {
  const el = page.getByText(new RegExp(`^${title}: \\d`)).or(page.getByLabel(new RegExp(`^${title}: \\d`))).first();
  return ((await el.getAttribute('aria-label')) ?? (await el.textContent()) ?? '').replace(`${title}: `, '').trim();
}

/** Pulsa −/+ de un paso a la vez, confirmando cada cambio, hasta llegar a la hora. */
async function stepTimeTo(page: Page, title: string, button: string, target: string) {
  for (let i = 0; i < 30 && (await timeOf(page, title)) !== target; i++) {
    const before = await timeOf(page, title);
    await btn(page, button).dispatchEvent('click');
    await expect.poll(() => timeOf(page, title), { timeout: 2_000 }).not.toBe(before);
  }
  expect(await timeOf(page, title)).toBe(target);
}

const toggle = (page: Page, name: string) =>
  page.getByRole('switch', { name }).or(page.getByRole('checkbox', { name })).or(page.getByLabel(name, { exact: true })).first();

test.describe.configure({ timeout: 90_000 });

test.describe('solicitudes en el panel del cuidador', () => {
  test('la solicitud llega al cuidador con contador; aceptar la pasa a la agenda y se completa', async ({ page }) => {
    await enterAsOwner(page);
    await bookWithCarlos(page);
    await switchDemo(page, 'Cuidador');

    await expect(tab(page, 'Solicitudes')).toBeVisible();
    await expect(seen(page, 'Daniela Dueña · Rocky')).toBeVisible();
    await expect(seen(page, /^Paseo · .+ 9:00 a 10:00$/)).toBeVisible();
    await expect(seen(page, 'Total $26.000')).toBeVisible();
    await expect(seen(page, /^Responde en (1 h \d+ min|2 h)$/)).toBeVisible();

    await btn(page, 'Aceptar').click();
    await expect(seen(page, 'Reserva aceptada')).toBeVisible();
    await expect(seen(page, 'No tienes solicitudes pendientes.')).toBeVisible();

    await tab(page, 'Agenda').click();
    await expect(seen(page, /Paseo/)).toBeVisible();
    await btn(page, 'Marcar completada').click();
    await expect(seen(page, 'Completadas')).toBeVisible();
    await expect(seen(page, /Completada/)).toBeVisible();
    await expect(btn(page, 'Marcar completada')).toHaveCount(0);
  });

  test('rechazar una solicitud', async ({ page }) => {
    await enterAsOwner(page);
    await bookWithCarlos(page);
    await switchDemo(page, 'Cuidador');
    await btn(page, 'Rechazar').click();
    await expect(seen(page, 'Solicitud rechazada')).toBeVisible();
    await expect(seen(page, 'No tienes solicitudes pendientes.')).toBeVisible();
    await tab(page, 'Agenda').click();
    await expect(seen(page, 'No tienes reservas aceptadas.')).toBeVisible();
  });

  test('sin solicitudes muestra el estado vacío', async ({ page }) => {
    await goToLogin(page);
    await page.getByRole('button', { name: 'Probar demo' }).click();
    await switchDemo(page, 'Cuidador');
    await expect(seen(page, 'No tienes solicitudes pendientes.')).toBeVisible();
  });

  test('si el cuidador no responde en 2 horas, la solicitud vence sola', async ({ page }) => {
    await page.clock.install();
    await enterAsOwner(page);
    await bookWithCarlos(page);
    await switchDemo(page, 'Cuidador');
    await expect(seen(page, 'Daniela Dueña · Rocky')).toBeVisible();

    await page.clock.fastForward('02:01:00');
    await expect(seen(page, 'No tienes solicitudes pendientes.')).toBeVisible({ timeout: 30_000 });
    await expect(btn(page, 'Aceptar')).toHaveCount(0);
  });
});

test.describe('perfil en revisión', () => {
  test('un cuidador nuevo ve "Tu perfil está en revisión" y puede preparar sus servicios', async ({ page }) => {
    await goToLogin(page);
    await btn(page, 'Crear cuenta').click();
    await btn(page, 'Soy cuidador').click();
    await typeInto(page, 'Nombre completo', 'Cuidadora Nueva');
    await typeInto(page, 'Correo', 'cuidadora.nueva@test.com');
    await typeInto(page, 'Contraseña', 'secreto1');
    await page.getByRole('checkbox').click();
    await page.getByRole('button', { name: 'Crear cuenta' }).last().click();

    await expect(seen(page, 'Tu perfil está en revisión')).toBeVisible();
    await expect(seen(page, /no apareces en el mapa/)).toBeVisible();
    await tab(page, 'Servicios').click();
    await expect(btn(page, 'Guardar servicios')).toBeVisible();
  });
});

test.describe('servicios y horario', () => {
  test('el cuidador cambia precios y activa un servicio; el dueño lo ve en el mapa y el perfil', async ({ page }) => {
    await enterAsOwner(page);
    await switchDemo(page, 'Cuidador');
    await tab(page, 'Servicios').click();

    await typeInto(page, 'Precio de Paseo', '30000');
    await toggle(page, 'Ofrecer Entrenamiento básico').click();
    await typeInto(page, 'Precio de Entrenamiento básico', '70000');
    await btn(page, 'Guardar servicios').click();
    await expect(seen(page, 'Servicios guardados')).toBeVisible();

    await switchDemo(page, 'Dueño');
    await expect(pin(page, 'Carlos Cuidador')).toHaveAccessibleName('Cuidador Carlos Cuidador, $30.000');
    await openProfileFromMap(page, 'Carlos Cuidador');
    await expect(seen(page, 'Entrenamiento básico, $70.000 por sesión')).toBeVisible();
  });

  test('un precio fuera de rango no se guarda', async ({ page }) => {
    await enterAsOwner(page);
    await switchDemo(page, 'Cuidador');
    await tab(page, 'Servicios').click();
    await typeInto(page, 'Precio de Paseo', '100');
    await btn(page, 'Guardar servicios').click();
    await expect(seen(page, 'Los precios deben estar entre $5.000 y $2.000.000.')).toBeVisible();
  });

  test('el horario del cuidador limita las horas que ve el dueño', async ({ page }) => {
    const tomorrow = new Date(Date.now() + 24 * 3600 * 1000);
    const day = ['Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'][tomorrow.getDay()];

    await enterAsOwner(page);
    await switchDemo(page, 'Cuidador');
    await tab(page, 'Servicios').click();

    // "Guardar horario" está debajo del domingo: al verlo, todas las filas de
    // días quedan completas en pantalla (Flutter omite lo que asoma a medias).
    await scrollUntil(page, btn(page, 'Guardar horario'));
    await page.mouse.wheel(0, 300);
    await page.waitForTimeout(300);

    await stepTimeTo(page, `${day} desde`, `${day} desde: más tarde`, '10:00');
    await stepTimeTo(page, `${day} hasta`, `${day} hasta: más temprano`, '12:00');
    await btn(page, 'Guardar horario').dispatchEvent('click');
    await expect(seen(page, 'Horario guardado')).toBeVisible();

    await switchDemo(page, 'Dueño');
    await openSheetFromMap(page, 'Carlos Cuidador');
    await stepTo(page, 'Día', 'Mañana', 'Día anterior', 'Día siguiente');
    await stepToEnd(page, 'Hora', 'Hora anterior');
    expect(await readValue(page, 'Hora')).toBe('10:00');
    await stepToEnd(page, 'Hora', 'Hora siguiente');
    expect(await readValue(page, 'Hora')).toBe('12:00');
  });
});
