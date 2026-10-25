import { test, expect, Page } from '@playwright/test';
import { btn, enterAsOwner, pin, scrollUntil, seen, switchDemo, tab, typeInto } from './helpers';

test.describe.configure({ timeout: 90_000 });

async function asSuperadmin(page: Page) {
  await enterAsOwner(page);
  await switchDemo(page, 'Superadministrador');
  await tab(page, 'Equipo').click();
  await expect(seen(page, 'Nombrar administrador')).toBeVisible();
}

test.describe('equipo', () => {
  test('nombra administrador por correo y queda en la auditoría', async ({ page }) => {
    await asSuperadmin(page);
    await expect(seen(page, /^Ana Admin/)).toBeVisible();

    await typeInto(page, 'Correo del nuevo administrador', 'dueno@doggo.app');
    await btn(page, 'Hacer administrador').click();
    await btn(page, 'Sí, nombrar').click();
    await expect(seen(page, 'Daniela Dueña ahora es administrador')).toBeVisible();
    await expect(btn(page, 'Quitar admin a Daniela Dueña')).toBeVisible();

    const log = seen(page, 'Sergio Superadmin nombró administrador a Daniela Dueña');
    await scrollUntil(page, log);
    await expect(log).toBeVisible();
  });

  test('un correo que no existe no nombra a nadie', async ({ page }) => {
    await asSuperadmin(page);
    await typeInto(page, 'Correo del nuevo administrador', 'nadie@doggo.app');
    await btn(page, 'Hacer administrador').click();
    await expect(seen(page, 'No hay ninguna cuenta con ese correo.')).toBeVisible();
  });

  test('quitar el rol: el admin pierde el panel y queda como dueño', async ({ page }) => {
    await asSuperadmin(page);
    await btn(page, 'Quitar admin a Ana Admin').click();
    await btn(page, 'Sí, quitar').click();
    await expect(seen(page, 'Ana Admin ya no es administrador')).toBeVisible();
    await expect(seen(page, 'Todavía no hay administradores.')).toBeVisible();

    // La cuenta de admin de la demo ahora entra como dueña.
    await tab(page, 'Perfil').click();
    await btn(page, 'Demo: Administrador').dispatchEvent('click');
    await expect(tab(page, 'Explorar')).toBeVisible();
    await expect(tab(page, 'Aprobaciones')).toHaveCount(0);
  });

  test('suspende y reactiva a un admin desde Equipo', async ({ page }) => {
    await asSuperadmin(page);
    await btn(page, 'Suspender a Ana Admin').click();
    await btn(page, 'Sí, suspender').click();
    await expect(seen(page, 'Ana Admin fue suspendido')).toBeVisible();
    await btn(page, 'Reactivar a Ana Admin').click();
    await expect(seen(page, 'Ana Admin fue reactivado')).toBeVisible();
  });
});

test.describe('eliminar cuentas', () => {
  test('el superadmin elimina una cuenta: sale del mapa y la auditoría la conserva', async ({ page }) => {
    await asSuperadmin(page);
    await tab(page, 'Usuarios').click();
    await typeInto(page, 'Buscar por nombre o correo', 'Julián');
    await btn(page, 'Eliminar cuenta de Julián Castro').click();
    await btn(page, 'Sí, eliminar').click();
    await expect(seen(page, 'La cuenta de Julián Castro fue eliminada')).toBeVisible();
    await expect(seen(page, 'Ningún usuario coincide con la búsqueda.')).toBeVisible();

    await tab(page, 'Equipo').click();
    const log = seen(page, 'Sergio Superadmin eliminó la cuenta de Julián Castro');
    await scrollUntil(page, log);
    await expect(log).toBeVisible();

    await switchDemo(page, 'Dueño');
    await expect(pin(page, 'Laura Gómez')).toBeAttached();
    await expect(pin(page, 'Julián Castro')).toHaveCount(0);
  });

  test('un admin no puede eliminar cuentas y solo ve su propio historial', async ({ page }) => {
    await enterAsOwner(page);
    await switchDemo(page, 'Administrador');
    await btn(page, 'Aprobar a Natalia Peña').click();
    await expect(seen(page, 'Natalia Peña fue aprobado')).toBeVisible();

    await tab(page, 'Usuarios').click();
    await typeInto(page, 'Buscar por nombre o correo', 'Julián');
    await expect(btn(page, 'Suspender a Julián Castro')).toBeVisible();
    await expect(btn(page, 'Eliminar cuenta de Julián Castro')).toHaveCount(0);

    const log = seen(page, 'Ana Admin aprobó a Natalia Peña');
    await scrollUntil(page, log);
    await expect(seen(page, 'Mi historial')).toBeVisible();
    await expect(log).toBeVisible();
  });
});
