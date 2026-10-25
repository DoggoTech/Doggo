import { test, expect, Page } from '@playwright/test';
import {
  btn, enterAsOwner, goToLogin, openProfileFromMap, pin, pins, scrollToEnd, seen, switchDemo, tab, typeInto, zonePin,
} from './helpers';

test.describe.configure({ timeout: 90_000 });

const toggle = (page: Page, name: string) =>
  page.getByRole('switch', { name }).or(page.getByRole('checkbox', { name })).or(page.getByLabel(name, { exact: true })).first();

async function asAdmin(page: Page, role: 'Administrador' | 'Superadministrador' = 'Administrador') {
  await enterAsOwner(page);
  await switchDemo(page, role);
  await expect(tab(page, 'Aprobaciones')).toBeVisible();
}

async function searchUser(page: Page, text: string) {
  await tab(page, 'Usuarios').click();
  await typeInto(page, 'Buscar por nombre o correo', text);
}

test.describe('aprobaciones', () => {
  test('aprobar a un cuidador en revisión lo pone en el mapa', async ({ page }) => {
    await asAdmin(page);
    await expect(seen(page, /^Natalia Peña/)).toBeVisible();
    await expect(seen(page, /^Ricardo Salazar/)).toBeVisible();

    await btn(page, 'Aprobar a Natalia Peña').click();
    await expect(seen(page, 'Natalia Peña fue aprobado')).toBeVisible();
    await expect(btn(page, 'Aprobar a Natalia Peña')).toHaveCount(0);

    await switchDemo(page, 'Dueño');
    await expect(pin(page, 'Natalia Peña')).toBeAttached();
    await expect(pins(page)).toHaveCount(12);
  });

  test('rechazar deja la cuenta suspendida', async ({ page }) => {
    await asAdmin(page);
    await btn(page, 'Rechazar a Ricardo Salazar').click();
    await btn(page, 'Sí, rechazar').click();
    await expect(seen(page, 'Ricardo Salazar fue rechazado')).toBeVisible();
    await searchUser(page, 'Ricardo');
    await expect(seen(page, 'Estado: Suspendido')).toBeVisible();
  });

  test('la insignia Verificado llega al perfil público', async ({ page }) => {
    await asAdmin(page);
    await toggle(page, 'Verificado: Natalia Peña').click();
    await expect(seen(page, 'Insignia actualizada')).toBeVisible();
    await btn(page, 'Aprobar a Natalia Peña').click();
    await expect(seen(page, 'Natalia Peña fue aprobado')).toBeVisible();
    await switchDemo(page, 'Dueño');
    await openProfileFromMap(page, 'Natalia Peña');
    await expect(seen(page, /Natalia Peña\s*Verificado/)).toBeVisible();
  });
});

test.describe('criterio de aceptación: aprobación', () => {
  test.use({ geolocation: { latitude: 4.628, longitude: -74.15 }, permissions: ['geolocation'] });

  test('un cuidador recién registrado no aparece en el mapa hasta que el admin lo aprueba', async ({ page }) => {
    await goToLogin(page);
    await btn(page, 'Crear cuenta').click();
    await btn(page, 'Soy cuidador').click();
    await typeInto(page, 'Nombre completo', 'Sitter Nuevo');
    await typeInto(page, 'Correo', 'sitter.nuevo@test.com');
    await typeInto(page, 'Contraseña', 'secreto1');
    await page.getByRole('checkbox').click();
    await page.getByRole('button', { name: 'Crear cuenta' }).last().click();
    await expect(seen(page, 'Tu perfil está en revisión')).toBeVisible();

    // Prepara su servicio mientras espera la aprobación.
    await tab(page, 'Servicios').click();
    await toggle(page, 'Ofrecer Paseo').click();
    await typeInto(page, 'Precio de Paseo', '20000');
    await btn(page, 'Guardar servicios').click();
    await expect(seen(page, 'Servicios guardados')).toBeVisible();
    // Y su zona de servicio, al final de la página (sin ella no saldría en el mapa).
    await scrollToEnd(page, btn(page, 'Guardar zona'));
    await btn(page, 'Usar mi ubicación actual').click();
    await expect(zonePin(page)).toBeAttached();
    await typeInto(page, 'Barrio', 'Kennedy');
    await btn(page, 'Guardar zona').click();
    await expect(seen(page, 'Zona guardada')).toBeVisible();

    await switchDemo(page, 'Dueño');
    await expect(pins(page).first()).toBeAttached();
    await expect(pin(page, 'Sitter Nuevo')).toHaveCount(0); // aún en revisión

    await switchDemo(page, 'Administrador');
    await btn(page, 'Aprobar a Sitter Nuevo').click();
    await expect(seen(page, 'Sitter Nuevo fue aprobado')).toBeVisible();

    await switchDemo(page, 'Dueño');
    await expect(pin(page, 'Sitter Nuevo')).toBeAttached(); // ya aprobado
    await pin(page, 'Sitter Nuevo').dispatchEvent('click');
    await expect(seen(page, /Kennedy · a /).first()).toBeVisible(); // su barrio, en la tarjeta
  });

});

test.describe('reportes', () => {
  async function reportLaura(page: Page) {
    await enterAsOwner(page);
    await openProfileFromMap(page, 'Laura Gómez');
    await btn(page, 'Reportar a Laura Gómez').click();
    await btn(page, 'Perfil falso').click();
    await typeInto(page, '¿Qué pasó? (opcional)', 'Las fotos no son suyas');
    await btn(page, 'Enviar reporte').click();
    await btn(page, 'Listo').click();
    await btn(page, 'Back').click();
    await switchDemo(page, 'Administrador');
    await tab(page, 'Reportes').click();
  }

  test('un reporte llega al admin, que suspende al reportado: desaparece del mapa', async ({ page }) => {
    await reportLaura(page);
    await expect(seen(page, 'Perfil falso')).toBeVisible();
    await expect(seen(page, 'Daniela Dueña reportó a Laura Gómez')).toBeVisible();
    await expect(seen(page, /Las fotos no son suyas/)).toBeVisible();

    await btn(page, 'Suspender a Laura Gómez').click();
    await btn(page, 'Sí, suspender').click();
    await expect(seen(page, 'Laura Gómez fue suspendido')).toBeVisible();
    await expect(seen(page, 'No hay reportes abiertos.')).toBeVisible();
    await btn(page, 'Atendidos (1)').click();
    await expect(seen(page, /Revisado/)).toBeVisible();

    await switchDemo(page, 'Dueño');
    await expect(pins(page).first()).toBeAttached();
    await expect(pin(page, 'Laura Gómez')).toHaveCount(0);
  });

  test('descartar un reporte', async ({ page }) => {
    await reportLaura(page);
    await btn(page, 'Descartar: reporte a Laura Gómez').click();
    await expect(seen(page, 'Reporte descartado')).toBeVisible();
    await expect(seen(page, 'No hay reportes abiertos.')).toBeVisible();
  });
});

test.describe('usuarios', () => {
  test('suspender a un cuidador lo saca del mapa y no puede entrar; reactivarlo lo devuelve', async ({ page }) => {
    await asAdmin(page);
    await searchUser(page, 'carlos');
    await btn(page, 'Suspender a Carlos Cuidador').click();
    await btn(page, 'Sí, suspender').click();
    await expect(seen(page, 'Carlos Cuidador fue suspendido')).toBeVisible();
    await expect(seen(page, 'Estado: Suspendido')).toBeVisible();

    await switchDemo(page, 'Dueño');
    await expect(pins(page).first()).toBeAttached();
    await expect(pin(page, 'Carlos Cuidador')).toHaveCount(0);

    await switchDemo(page, 'Administrador');
    await searchUser(page, 'carlos');
    await btn(page, 'Reactivar a Carlos Cuidador').click();
    await expect(seen(page, 'Carlos Cuidador fue reactivado')).toBeVisible();
    await switchDemo(page, 'Dueño');
    await expect(pin(page, 'Carlos Cuidador')).toBeAttached();
  });

  test('una cuenta suspendida no puede iniciar sesión', async ({ page }) => {
    await asAdmin(page);
    await searchUser(page, 'carlos');
    await btn(page, 'Suspender a Carlos Cuidador').click();
    await btn(page, 'Sí, suspender').click();
    await expect(seen(page, 'Carlos Cuidador fue suspendido')).toBeVisible();
    await tab(page, 'Perfil').click();
    await btn(page, 'Demo: Cuidador').click();
    await expect(seen(page, /Tu cuenta está suspendida/)).toBeVisible();
    await expect(seen(page, 'Iniciar sesión')).toBeVisible();
  });

  test('un admin no puede tocar al superadmin ni a sí mismo', async ({ page }) => {
    await asAdmin(page);
    await searchUser(page, 'Sergio');
    await expect(seen(page, 'Protegido: Sergio Superadmin')).toBeVisible();
    await expect(btn(page, 'Suspender a Sergio Superadmin')).toHaveCount(0);
    await typeInto(page, 'Buscar por nombre o correo', 'Ana');
    await expect(seen(page, 'Tú: Ana Admin')).toBeVisible();
  });

  test('el superadmin sí puede suspender a un admin', async ({ page }) => {
    await asAdmin(page, 'Superadministrador');
    await searchUser(page, 'Ana');
    await expect(btn(page, 'Suspender a Ana Admin')).toBeVisible();
  });

  test('filtros por rol y estado', async ({ page }) => {
    await asAdmin(page);
    await tab(page, 'Usuarios').click();
    await btn(page, 'En revisión').click();
    await expect(seen(page, /^Natalia Peña/)).toBeVisible();
    await expect(seen(page, /^Ricardo Salazar/)).toBeVisible();
    await expect(seen(page, /^Laura Gómez/)).toHaveCount(0);
    await btn(page, 'Cualquier estado').click();
    await btn(page, 'Admins').click();
    await expect(seen(page, /^Ana Admin/)).toBeVisible();
    await expect(seen(page, /^Carlos Cuidador/)).toHaveCount(0);
  });
});
