import { test, expect } from '@playwright/test';
import { goToLogin, login, scrollUntil, tab, texto, typeInto } from './helpers';

test.describe('login por rol', () => {
  const cases = [
    { email: 'dueno@doggo.app', visibles: ['Explorar', 'Reservas', 'Perros', 'Perfil'], ausentes: ['Equipo'] },
    { email: 'cuidador@doggo.app', visibles: ['Solicitudes', 'Agenda', 'Servicios', 'Perfil'], ausentes: ['Explorar'] },
    { email: 'admin@doggo.app', visibles: ['Aprobaciones', 'Reportes', 'Usuarios', 'Perfil'], ausentes: ['Equipo'] },
    { email: 'superadmin@doggo.app', visibles: ['Aprobaciones', 'Reportes', 'Usuarios', 'Equipo', 'Perfil'], ausentes: [] },
  ];
  for (const c of cases) {
    test(`${c.email} ve su navegación`, async ({ page }) => {
      await goToLogin(page);
      await login(page, c.email);
      for (const t of c.visibles) await expect(tab(page, t)).toBeVisible();
      for (const t of c.ausentes) await expect(tab(page, t)).toHaveCount(0);
    });
  }
});

test('contraseña incorrecta muestra error y no entra', async ({ page }) => {
  await goToLogin(page);
  await login(page, 'dueno@doggo.app', 'mala-clave');
  await expect(texto(page, 'Correo o contraseña incorrectos.')).toBeVisible();
  await expect(tab(page, 'Explorar')).toHaveCount(0);
});

test('cuenta suspendida ve el aviso y no entra', async ({ page }) => {
  await goToLogin(page);
  await login(page, 'suspendido@doggo.app');
  await expect(texto(page, 'Tu cuenta está suspendida')).toBeVisible();
  await expect(tab(page, 'Explorar')).toHaveCount(0);
});

test('"Probar demo" entra como dueño sin credenciales', async ({ page }) => {
  await goToLogin(page);
  await page.getByRole('button', { name: 'Probar demo' }).click();
  await expect(tab(page, 'Explorar')).toBeVisible();
});

test('cerrar sesión vuelve al login y protege /home', async ({ page }) => {
  await goToLogin(page);
  await page.getByRole('button', { name: 'Probar demo' }).click();
  await tab(page, 'Perfil').click();
  // Al final del perfil: tras desplazarse puede quedar a medio asomar, así que
  // se activa directamente (como un lector de pantalla).
  await scrollUntil(page, page.getByRole('button', { name: 'Cerrar sesión' }));
  await page.getByRole('button', { name: 'Cerrar sesión' }).dispatchEvent('click');
  await expect(page.getByText('Iniciar sesión')).toBeVisible();
  await expect(tab(page, 'Perfil')).toHaveCount(0);
});

test.describe('registro', () => {
  async function fill(page: import('@playwright/test').Page, email: string, rol: 'dueño' | 'cuidador') {
    await page.getByRole('button', { name: 'Crear cuenta' }).click();
    await expect(page.getByText('Crear cuenta').first()).toBeVisible();
    await page.getByRole('button', { name: rol === 'dueño' ? 'Soy dueño' : 'Soy cuidador' }).click();
    await typeInto(page, 'Nombre completo', 'Persona Nueva');
    await typeInto(page, 'Correo', email);
    await typeInto(page, 'Contraseña', 'secreto1');
  }
  const submit = (page: import('@playwright/test').Page) =>
    page.getByRole('button', { name: 'Crear cuenta' }).last().click();

  test('sin aceptar los términos 18+ no se registra', async ({ page }) => {
    await goToLogin(page);
    await fill(page, 'nuevo@test.com', 'dueño');
    await submit(page);
    await expect(texto(page, 'Debes confirmar que eres mayor de 18')).toBeVisible();
  });

  test('dueño nuevo entra y ve su navegación', async ({ page }) => {
    await goToLogin(page);
    await fill(page, 'nuevo.dueno@test.com', 'dueño');
    await page.getByRole('checkbox').click();
    await submit(page);
    await expect(tab(page, 'Explorar')).toBeVisible();
  });

  test('cuidador nuevo entra con navegación de cuidador', async ({ page }) => {
    await goToLogin(page);
    await fill(page, 'nuevo.cuidador@test.com', 'cuidador');
    await page.getByRole('checkbox').click();
    await submit(page);
    await expect(tab(page, 'Solicitudes')).toBeVisible();
  });

  test('correo repetido muestra error', async ({ page }) => {
    await goToLogin(page);
    await fill(page, 'dueno@doggo.app', 'dueño');
    await page.getByRole('checkbox').click();
    await submit(page);
    await expect(texto(page, 'Ya existe una cuenta con ese correo.')).toBeVisible();
  });

  test('el registro no ofrece roles admin ni superadmin', async ({ page }) => {
    await goToLogin(page);
    await page.getByRole('button', { name: 'Crear cuenta' }).click();
    await expect(page.getByRole('button', { name: 'Soy dueño' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Soy cuidador' })).toBeVisible();
    await expect(page.getByText(/admin/i)).toHaveCount(0);
  });
});

test.describe('perfil y cambio de rol', () => {
  test('dueño cambia a cuidador desde ajustes', async ({ page }) => {
    await goToLogin(page);
    await page.getByRole('button', { name: 'Probar demo' }).click();
    await tab(page, 'Perfil').click();
    await expect(page.getByText('Rol: Dueño')).toBeVisible();
    await page.getByRole('button', { name: 'Cambiar a cuidador' }).click();
    await expect(tab(page, 'Solicitudes')).toBeVisible();
    await tab(page, 'Perfil').click();
    await expect(page.getByText('Rol: Cuidador')).toBeVisible();
  });

  test('modo demo permite recorrer los 4 roles sin cerrar sesión', async ({ page }) => {
    await goToLogin(page);
    await page.getByRole('button', { name: 'Probar demo' }).click();
    await tab(page, 'Perfil').click();
    await page.getByRole('button', { name: 'Demo: Superadministrador' }).click();
    await expect(tab(page, 'Equipo')).toBeVisible();
    await tab(page, 'Perfil').click();
    await page.getByRole('button', { name: 'Demo: Cuidador' }).click();
    await expect(tab(page, 'Solicitudes')).toBeVisible();
  });

  test('admin no tiene opción de cambiar rol', async ({ page }) => {
    await goToLogin(page);
    await login(page, 'admin@doggo.app');
    await tab(page, 'Perfil').click();
    await expect(page.getByText('Rol: Administrador')).toBeVisible();
    await expect(page.getByRole('button', { name: /^Cambiar a/ })).toHaveCount(0);
  });
});
