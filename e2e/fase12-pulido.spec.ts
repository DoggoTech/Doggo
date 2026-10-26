import { test, expect } from '@playwright/test';
import { btn, enterAsOwner, goToLogin, pins, scrollUntil, seen, switchDemo, tab, typeInto } from './helpers';

const groups = (page: import('@playwright/test').Page) =>
  page.getByRole('button', { name: /^\d+ cuidadores en esta zona, desde \$[\d.]+\. Acercar$/ });

test.describe('pines agrupados', () => {
  test.use({ viewport: { width: 390, height: 780 } });

  test('los pines que se tapan forman un grupo; tocarlo acerca y los separa', async ({ page }) => {
    await enterAsOwner(page);
    await expect(groups(page).first()).toBeAttached();
    // Con lector de pantalla, cada cuidador del grupo sigue siendo un pin propio.
    await expect(pins(page)).toHaveCount(11);

    const before = await groups(page).count();
    await groups(page).first().dispatchEvent('click');
    await expect(async () => expect(await groups(page).count()).toBeLessThan(before)).toPass();
    await expect(pins(page).first()).toBeAttached();
  });

  test('un cuidador dentro de un grupo se puede abrir directo', async ({ page }) => {
    await enterAsOwner(page);
    const before = await groups(page).count();
    expect(before).toBeGreaterThan(0);
    // Julián ($20.000) arranca agrupado con sus vecinos del centro. Tocar su
    // pin lo selecciona y lo saca del grupo.
    await page.getByRole('button', { name: /^Cuidador Julián Castro, / }).dispatchEvent('click');
    await expect(page.getByRole('button', { name: 'Cerrar' })).toBeVisible();
    await expect(page.getByText(/Julián Castro\s*Verificado/)).toBeVisible();
  });
});

test.describe('aviso del cuidador fuera del mapa', () => {
  test('aprobado sin servicios ni zona: Solicitudes le dice qué le falta', async ({ page }) => {
    await goToLogin(page);
    await btn(page, 'Crear cuenta').click();
    await btn(page, 'Soy cuidador').click();
    await typeInto(page, 'Nombre completo', 'Santi Sin Servicios');
    await typeInto(page, 'Correo', 'santi.sin@test.com');
    await typeInto(page, 'Contraseña', 'secreto1');
    await page.getByRole('checkbox').click();
    await page.getByRole('button', { name: 'Crear cuenta' }).last().click();
    await expect(seen(page, 'Tu perfil está en revisión')).toBeVisible();

    await switchDemo(page, 'Administrador');
    await btn(page, 'Aprobar a Santi Sin Servicios').click();
    await expect(seen(page, 'Santi Sin Servicios fue aprobado')).toBeVisible();

    // Vuelve a entrar con su cuenta: ya aprobado, pero nadie lo encuentra.
    await tab(page, 'Perfil').click();
    await scrollUntil(page, btn(page, 'Cerrar sesión'));
    await btn(page, 'Cerrar sesión').dispatchEvent('click');
    await typeInto(page, 'Correo', 'santi.sin@test.com');
    await typeInto(page, 'Contraseña', 'secreto1');
    await btn(page, 'Entrar').click();
    await expect(tab(page, 'Solicitudes')).toBeVisible();
    await expect(
      seen(page, 'Aún no sales en el mapa. Te falta activar al menos un servicio con su precio y definir tu zona de servicio (en la pestaña Servicios).'),
    ).toBeVisible();
  });

  test('Carlos, con servicios y zona, no ve el aviso', async ({ page }) => {
    await enterAsOwner(page);
    await switchDemo(page, 'Cuidador');
    await expect(seen(page, 'No tienes solicitudes pendientes.')).toBeVisible();
    await expect(seen(page, /^Aún no sales en el mapa/)).toHaveCount(0);
  });
});
