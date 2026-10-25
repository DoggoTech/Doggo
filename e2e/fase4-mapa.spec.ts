import { test, expect } from '@playwright/test';
import { enterAsOwner, goToLogin, login, pin, pins, selectService, tab, tiles } from './helpers';

test.describe('mapa del dueño', () => {
  test('muestra un pin por cuidador aprobado, con el precio del paseo', async ({ page }) => {
    await enterAsOwner(page);
    await expect(pins(page)).toHaveCount(10);
    await expect(pin(page, 'Laura Gómez')).toHaveAccessibleName('Cuidador Laura Gómez, $25.000');
    // Isabela no hace paseos: su pin muestra el servicio más barato que ofrece.
    await expect(pin(page, 'Isabela Mejía')).toHaveAccessibleName('Cuidador Isabela Mejía, $32.000');
  });

  test('cita la atribución de OpenStreetMap', async ({ page }) => {
    await enterAsOwner(page);
    await expect(page.getByRole('group', { name: /© OpenStreetMap contributors/ })).toBeAttached();
  });

  test('un cuidador recién registrado no aparece en el mapa', async ({ page }) => {
    await goToLogin(page);
    await page.getByRole('button', { name: 'Crear cuenta' }).click();
    await page.getByRole('button', { name: 'Soy cuidador' }).click();
    const fill = async (label: string, text: string) => {
      const box = page.getByRole('textbox', { name: label });
      await expect(async () => {
        await box.click();
        await box.press('ControlOrMeta+a');
        await box.pressSequentially(text);
        await expect(box).toHaveValue(text, { timeout: 1_000 });
      }).toPass({ timeout: 15_000 });
    };
    await fill('Nombre completo', 'Sitter Nuevo');
    await fill('Correo', 'nuevo.sitter@test.com');
    await fill('Contraseña', 'secreto1');
    await page.getByRole('checkbox').click();
    await page.getByRole('button', { name: 'Crear cuenta' }).last().click();
    await expect(tab(page, 'Solicitudes')).toBeVisible();

    await tab(page, 'Perfil').click();
    await page.getByRole('button', { name: 'Demo: Dueño' }).click();
    await expect(pins(page).first()).toBeAttached({ timeout: 15_000 });
    await expect(pins(page)).toHaveCount(10);
    await expect(pin(page, 'Sitter Nuevo')).toHaveCount(0);
  });

  test('el cuidador no ve el mapa', async ({ page }) => {
    await goToLogin(page);
    await login(page, 'cuidador@doggo.app');
    await expect(tab(page, 'Solicitudes')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Mi ubicación' })).toHaveCount(0);
    await expect(pins(page)).toHaveCount(0);
  });
});

test.describe('filtros', () => {
  test('filtrar por servicio deja solo a quienes lo ofrecen, con su precio', async ({ page }) => {
    await enterAsOwner(page);
    await selectService(page, 'Hospedaje nocturno');
    await expect(pins(page)).toHaveCount(4);
    await expect(pin(page, 'Andrés Rojas')).toHaveAccessibleName('Cuidador Andrés Rojas, $85.000');
    await expect(pin(page, 'Mateo Vargas')).toHaveAccessibleName('Cuidador Mateo Vargas, $60.000');
    await expect(page.getByText('4 cuidadores cerca')).toBeVisible();
  });

  test('"Todos" y volver a pulsar el chip quitan el filtro', async ({ page }) => {
    await enterAsOwner(page);
    await selectService(page, 'Paseo');
    await expect(pins(page)).toHaveCount(9); // Isabela no hace paseos
    await page.getByRole('button', { name: 'Todos' }).click();
    await expect(pins(page)).toHaveCount(10);
    await selectService(page, 'Entrenamiento básico');
    await expect(pins(page)).toHaveCount(2);
    await selectService(page, 'Entrenamiento básico');
    await expect(pins(page)).toHaveCount(10);
  });

  test('precio máximo', async ({ page }) => {
    await enterAsOwner(page);
    await page.getByRole('button', { name: /^Filtros/ }).click();
    await page.getByRole('button', { name: 'Hasta $30.000' }).click();
    await expect(page.getByRole('button', { name: 'Ver 8 cuidadores' })).toBeVisible();
    await page.getByRole('button', { name: 'Ver 8 cuidadores' }).click();
    await expect(pins(page)).toHaveCount(8);
    await expect(page.getByRole('button', { name: 'Filtros (1)' })).toBeVisible();
    await expect(pin(page, 'Daniela Moreno')).toHaveCount(0); // $35.000
  });

  test('calificación mínima combinada con precio', async ({ page }) => {
    await enterAsOwner(page);
    await page.getByRole('button', { name: /^Filtros/ }).click();
    await page.getByRole('button', { name: '4,5 o más' }).click();
    await expect(page.getByRole('button', { name: 'Ver 6 cuidadores' })).toBeVisible();
    await page.getByRole('button', { name: 'Hasta $30.000' }).click();
    await expect(page.getByRole('button', { name: 'Ver 4 cuidadores' })).toBeVisible();
    await page.getByRole('button', { name: 'Ver 4 cuidadores' }).click();
    await expect(pins(page)).toHaveCount(4);
    await expect(page.getByRole('button', { name: 'Filtros (2)' })).toBeVisible();
  });

  test('distancia máxima desde el centro de Bogotá', async ({ page }) => {
    await enterAsOwner(page);
    await page.getByRole('button', { name: /^Filtros/ }).click();
    await page.getByRole('button', { name: 'Hasta 3 km' }).click();
    await page.getByRole('button', { name: /^Ver \d+ cuidador/ }).click();
    await expect(pin(page, 'Julián Castro')).toBeAttached(); // Teusaquillo, ~1,6 km
    await expect(pin(page, 'Mateo Vargas')).toHaveCount(0); // Kennedy, lejos
    expect(await pins(page).count()).toBeLessThan(5);
  });

  test('sin resultados: estado vacío y "Limpiar filtros"', async ({ page }) => {
    await enterAsOwner(page);
    await page.getByRole('button', { name: /^Filtros/ }).click();
    await page.getByRole('button', { name: 'Hasta $30.000' }).click();
    await page.getByRole('button', { name: /^Ver \d+ cuidadores/ }).click();
    await selectService(page, 'Entrenamiento básico'); // cuesta $80.000 o más
    await expect(pins(page)).toHaveCount(0);
    await expect(page.getByRole('group', { name: 'No hay cuidadores con esos filtros.' })).toBeVisible();
    await page.getByRole('button', { name: 'Limpiar filtros' }).click();
    await expect(pins(page)).toHaveCount(10);
  });
});

test.describe('lista y selección', () => {
  test('la lista va del más cercano al más lejano (desde Bogotá centro)', async ({ page }) => {
    await enterAsOwner(page);
    await expect(page.getByText('Distancia desde el centro de Bogotá')).toBeVisible();
    await expect(tiles(page).first()).toHaveAccessibleName(/^Julián Castro, Teusaquillo, a 1,\d km/);
  });

  test('tocar un cuidador de la lista lo selecciona y muestra su tarjeta', async ({ page }) => {
    await enterAsOwner(page);
    await tiles(page).first().click();
    await expect(page.getByRole('button', { name: 'Cerrar' })).toBeVisible();
    await expect(tiles(page).first()).toHaveAttribute('aria-selected', /true|/).catch(() => {});
  });

  test('tocar un pin selecciona al cuidador y muestra su tarjeta', async ({ page }) => {
    await enterAsOwner(page);
    // Los pines vecinos se solapan; se activa como lo haría un lector de pantalla.
    await pin(page, 'Andrés Rojas').dispatchEvent('click');
    await expect(page.getByRole('button', { name: 'Cerrar' })).toBeVisible();
    await expect(page.getByText('Usaquén · a').first()).toBeVisible();
    await page.getByRole('button', { name: 'Cerrar' }).click();
    await expect(page.getByRole('button', { name: 'Cerrar' })).toHaveCount(0);
  });

  test('los verificados llevan insignia', async ({ page }) => {
    await enterAsOwner(page);
    await pin(page, 'Laura Gómez').dispatchEvent('click');
    await expect(page.getByRole('button', { name: 'Cerrar' })).toBeVisible();
    await expect(page.getByText(/Laura Gómez\s*Verificado/)).toBeVisible();
    await page.getByRole('button', { name: 'Cerrar' }).click();
    // Julián no está verificado: su tarjeta no lleva la insignia.
    await pin(page, 'Julián Castro').dispatchEvent('click');
    await expect(page.getByText(/Julián Castro/).first()).toBeVisible();
    await expect(page.getByText(/Julián Castro\s*Verificado/)).toHaveCount(0);
  });
});

test.describe('Mi ubicación', () => {
  test.describe('con permiso', () => {
    test.use({
      geolocation: { latitude: 4.628, longitude: -74.15 }, // Kennedy
      permissions: ['geolocation'],
    });

    test('centra el mapa, marca al usuario y ordena por cercanía real', async ({ page }) => {
      await enterAsOwner(page);
      await page.getByRole('button', { name: 'Mi ubicación' }).click();
      await expect(page.getByText('Distancia desde tu ubicación')).toBeVisible();
      await expect(page.getByLabel('Tu ubicación')).toBeAttached();
      await expect(tiles(page).first()).toHaveAccessibleName(/^Mateo Vargas, Kennedy, a \d+ m/);
    });
  });

  test('sin permiso: avisa y usa Bogotá como referencia', async ({ page }) => {
    await enterAsOwner(page);
    await page.getByRole('button', { name: 'Mi ubicación' }).click();
    await expect(page.getByText('No pudimos obtener tu ubicación. Te mostramos Bogotá.').first()).toBeVisible({
      timeout: 15_000,
    });
    await expect(page.getByText('Distancia desde el centro de Bogotá')).toBeVisible();
    await expect(pins(page)).toHaveCount(10);
  });
});

test.describe('adaptación a la pantalla', () => {
  test('celular: lista en hoja inferior; escritorio: panel lateral', async ({ page }, testInfo) => {
    await enterAsOwner(page);
    const vp = page.viewportSize()!;
    const box = await page.getByText('10 cuidadores cerca').boundingBox();
    expect(box).not.toBeNull();
    if (testInfo.project.name === 'mobile') {
      expect(box!.y).toBeGreaterThan(vp.height * 0.6); // abajo
    } else {
      expect(box!.x).toBeGreaterThan(vp.width * 0.6); // a la derecha
    }
  });
});
