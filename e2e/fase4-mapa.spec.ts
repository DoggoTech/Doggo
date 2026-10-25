import { test, expect } from '@playwright/test';
import { enterAsOwner, goToLogin, login, openApp, pin, pins, selectService, switchDemo, tab, tiles } from './helpers';

test.describe('mapa del dueño', () => {
  test('muestra un pin por cuidador aprobado, con el precio del paseo', async ({ page }) => {
    await enterAsOwner(page);
    await expect(pins(page)).toHaveCount(11);
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

    await switchDemo(page, 'Dueño');
    await expect(pins(page).first()).toBeAttached({ timeout: 15_000 });
    await expect(pins(page)).toHaveCount(11);
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
    await expect(pins(page)).toHaveCount(10); // todos menos Isabela, que no hace paseos
    await page.getByRole('button', { name: 'Todos' }).click();
    await expect(pins(page)).toHaveCount(11);
    await selectService(page, 'Entrenamiento básico');
    await expect(pins(page)).toHaveCount(2);
    await selectService(page, 'Entrenamiento básico');
    await expect(pins(page)).toHaveCount(11);
  });

  test('precio máximo', async ({ page }) => {
    await enterAsOwner(page);
    await page.getByRole('button', { name: /^Filtros/ }).click();
    await page.getByRole('button', { name: 'Hasta $30.000' }).click();
    await expect(page.getByRole('button', { name: 'Ver 9 cuidadores' })).toBeVisible();
    await page.getByRole('button', { name: 'Ver 9 cuidadores' }).click();
    await expect(pins(page)).toHaveCount(9);
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
    await expect(pins(page)).toHaveCount(11);
  });
});

test.describe('lista y selección', () => {
  test('la lista va del más cercano al más lejano (desde Bogotá centro)', async ({ page }) => {
    await enterAsOwner(page);
    await expect(page.getByText('Distancia desde el centro de Bogotá')).toBeVisible();
    await expect(tiles(page).first()).toHaveAccessibleName(/^Julián Castro, Teusaquillo, a 1,\d km/);
  });

  test('tocar un cuidador de la lista abre su perfil', async ({ page }) => {
    await enterAsOwner(page);
    await tiles(page).first().click();
    await expect(page.getByText('Perfil del cuidador')).toBeVisible();
    await expect(page.getByText('Julián Castro').first()).toBeVisible();
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

    const KENNEDY = { latitude: 4.628, longitude: -74.15 };
    const CANDELARIA = { latitude: 4.596, longitude: -74.073 };
    const button = (page: import('@playwright/test').Page, name: string) =>
      page.getByRole('button', { name, exact: true });

    test('centra el mapa, marca al usuario y ordena por cercanía real', async ({ page }) => {
      await enterAsOwner(page);
      await button(page, 'Mi ubicación').click();
      await expect(page.getByText('Distancia desde tu ubicación (en vivo)')).toBeVisible();
      await expect(page.getByLabel('Tu ubicación')).toBeAttached();
      await expect(tiles(page).first()).toHaveAccessibleName(/^Mateo Vargas, Kennedy, a \d+ m/);
    });

    test('sigue tu ubicación en tiempo real: el punto y el orden se actualizan solos', async ({ page, context }) => {
      await enterAsOwner(page);
      await button(page, 'Mi ubicación').click();
      await expect(button(page, 'Dejar de seguir mi ubicación')).toBeVisible();
      await expect(tiles(page).first()).toHaveAccessibleName(/^Mateo Vargas/);

      // El usuario "viaja" de Kennedy a La Candelaria, sin tocar nada en la app.
      await context.setGeolocation(CANDELARIA);
      await expect(tiles(page).first()).toHaveAccessibleName(/^Felipe Cárdenas, La Candelaria, a \d+ m/, {
        timeout: 15_000,
      });

      await context.setGeolocation(KENNEDY);
      await expect(tiles(page).first()).toHaveAccessibleName(/^Mateo Vargas/, { timeout: 15_000 });
    });

    test('un segundo toque deja de seguir y vuelve a Bogotá como referencia', async ({ page, context }) => {
      await enterAsOwner(page);
      await button(page, 'Mi ubicación').click();
      await expect(button(page, 'Dejar de seguir mi ubicación')).toBeVisible();

      await button(page, 'Dejar de seguir mi ubicación').click();
      await expect(button(page, 'Mi ubicación')).toBeVisible();
      await expect(page.getByLabel('Tu ubicación')).toHaveCount(0);
      await expect(page.getByText('Distancia desde el centro de Bogotá')).toBeVisible();
      await expect(tiles(page).first()).toHaveAccessibleName(/^Julián Castro/);

      // Ya no sigue: mover la ubicación no cambia nada.
      await context.setGeolocation(CANDELARIA);
      await page.waitForTimeout(1500);
      await expect(tiles(page).first()).toHaveAccessibleName(/^Julián Castro/);
    });

    test('al mover el mapa deja de acompañarte y se puede volver a centrar', async ({ page }) => {
      await enterAsOwner(page);
      await button(page, 'Mi ubicación').click();
      await expect(button(page, 'Dejar de seguir mi ubicación')).toBeVisible();

      // Un gesto del usuario (aquí, zoom con la rueda) le quita el control al seguimiento.
      const vp = page.viewportSize()!;
      await page.mouse.move(vp.width * 0.4, vp.height * 0.4);
      await page.mouse.wheel(0, -300);

      await expect(button(page, 'Volver a mi ubicación')).toBeVisible();
      // Sigue localizado (punto y lista en vivo), solo que el mapa ya no te persigue.
      await expect(page.getByLabel('Tu ubicación')).toBeAttached();
      await expect(page.getByText('Distancia desde tu ubicación (en vivo)')).toBeVisible();

      await button(page, 'Volver a mi ubicación').click();
      await expect(button(page, 'Dejar de seguir mi ubicación')).toBeVisible();
    });

    test('al salir del mapa se detiene el seguimiento (ahorra batería)', async ({ page }) => {
      await enterAsOwner(page);
      await button(page, 'Mi ubicación').click();
      await expect(button(page, 'Dejar de seguir mi ubicación')).toBeVisible();

      await tab(page, 'Perfil').click();
      await tab(page, 'Explorar').click();
      await expect(pins(page).first()).toBeAttached();
      await expect(button(page, 'Mi ubicación')).toBeVisible();
      await expect(page.getByLabel('Tu ubicación')).toHaveCount(0);
    });
  });

  test('sin permiso: avisa y usa Bogotá como referencia', async ({ page }) => {
    await enterAsOwner(page);
    await page.getByRole('button', { name: 'Mi ubicación' }).click();
    await expect(page.getByText('No pudimos obtener tu ubicación. Te mostramos Bogotá.').first()).toBeVisible({
      timeout: 15_000,
    });
    await expect(page.getByText('Distancia desde el centro de Bogotá')).toBeVisible();
    await expect(pins(page)).toHaveCount(11);
  });
});

test.describe('adaptación a la pantalla', () => {
  test('celular: lista en hoja inferior; escritorio: panel lateral', async ({ page }, testInfo) => {
    await enterAsOwner(page);
    const vp = page.viewportSize()!;
    const box = await page.getByText('11 cuidadores cerca').boundingBox();
    expect(box).not.toBeNull();
    if (testInfo.project.name === 'mobile') {
      expect(box!.y).toBeGreaterThan(vp.height * 0.6); // abajo
    } else {
      expect(box!.x).toBeGreaterThan(vp.width * 0.6); // a la derecha
    }
  });
});

test.describe('mover el mapa con el mouse', () => {
  // Regresión: forzar la accesibilidad de Flutter ponía una capa de elementos
  // sobre el canvas y, con el seguimiento de ubicación activo, el arrastre con
  // mouse no llegaba al mapa. Aquí la accesibilidad está apagada, igual que para
  // un usuario normal: se navega con teclado y mouse y se compara el dibujo.
  test.use({ geolocation: { latitude: 4.628, longitude: -74.15 }, permissions: ['geolocation'] });

  test('arrastrar el mapa lo desplaza, también siguiendo tu ubicación', async ({ page }, testInfo) => {
    test.skip(testInfo.project.name === 'mobile', 'el arrastre con mouse es de escritorio');
    await openApp(page, '/', { semantics: false });
    await page.waitForTimeout(3500); // splash
    await page.keyboard.press('Tab'); // "Saltar"
    await page.keyboard.press('Enter');
    await page.waitForTimeout(1500);
    for (let i = 0; i < 4; i++) await page.keyboard.press('Tab'); // Correo, Contraseña, Entrar, Probar demo
    await page.keyboard.press('Enter');
    await page.waitForTimeout(3500); // login + mapa

    await page.mouse.click(838, 666); // botón "Mi ubicación" (escritorio 1280x720)
    await page.waitForTimeout(1500);

    const area = { x: 100, y: 120, width: 700, height: 500 }; // solo el mapa, sin la lista
    // Control: sin tocar nada, el dibujo debe estar quieto. Así una diferencia
    // posterior solo puede venir del arrastre.
    const settled = async () => {
      let previous = await page.screenshot({ clip: area });
      for (let i = 0; i < 10; i++) {
        await page.waitForTimeout(500);
        const current = await page.screenshot({ clip: area });
        if (Buffer.compare(previous, current) === 0) return current;
        previous = current;
      }
      throw new Error('el mapa no se estabiliza antes de arrastrar');
    };
    const before = await settled();

    await page.mouse.move(400, 400);
    await page.mouse.down();
    await page.mouse.move(500, 470, { steps: 10 });
    await page.mouse.up();
    await page.waitForTimeout(800);
    const after = await page.screenshot({ clip: area });

    expect(Buffer.compare(before, after)).not.toBe(0);
  });
});
