import { test, expect } from '@playwright/test';
import { goToLogin, tab } from './helpers';

test('la navegación se adapta: barra inferior en celular, riel lateral en escritorio', async ({ page }, testInfo) => {
  await goToLogin(page);
  await page.getByRole('button', { name: 'Probar demo' }).click();

  const box = await tab(page, 'Explorar').boundingBox();
  const vp = page.viewportSize()!;
  expect(box).not.toBeNull();

  if (testInfo.project.name === 'mobile') {
    expect(box!.y).toBeGreaterThan(vp.height * 0.8); // abajo
  } else {
    expect(box!.x).toBeLessThan(160); // a la izquierda
    expect(box!.y).toBeLessThan(vp.height * 0.5); // no pegada al fondo
  }
});

test('en escritorio ancho el contenido no se estira de lado a lado', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name === 'mobile');
  await page.setViewportSize({ width: 1600, height: 900 });
  await goToLogin(page);
  await page.getByRole('button', { name: 'Probar demo' }).click();
  await tab(page, 'Perfil').click();
  const box = await page.getByRole('button', { name: 'Cerrar sesión' }).boundingBox();
  expect(box!.width).toBeLessThanOrEqual(960);
});
