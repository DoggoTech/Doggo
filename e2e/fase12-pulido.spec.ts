import { test, expect } from '@playwright/test';
import { enterAsOwner, pins } from './helpers';

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
