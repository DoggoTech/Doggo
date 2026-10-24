import { test, expect } from '@playwright/test';
import { openApp } from './helpers';

const titulo = (page: import('@playwright/test').Page, t: string) =>
  page.getByText(t);

test('splash → onboarding → 3 slides → login', async ({ page }) => {
  await openApp(page);
  await expect(page.getByLabel('Logo de Doggo').first()).toBeVisible({ timeout: 15_000 });

  await expect(titulo(page, 'Encuentra cuidadores cerca')).toBeVisible({ timeout: 15_000 });
  await page.getByRole('button', { name: 'Siguiente' }).click();
  await expect(titulo(page, 'Reserva en un toque')).toBeVisible();
  await page.getByRole('button', { name: 'Siguiente' }).click();
  await expect(titulo(page, 'Sigue tu reserva en vivo')).toBeVisible();

  await page.getByRole('button', { name: 'Empezar' }).click();
  await expect(titulo(page, 'Iniciar sesión')).toBeVisible();
});

test('Saltar lleva directo al login', async ({ page }) => {
  await openApp(page);
  await page.getByRole('button', { name: 'Saltar' }).click({ timeout: 15_000 });
  await expect(titulo(page, 'Iniciar sesión')).toBeVisible();
});

test('al volver a abrir la app va directo al login', async ({ page }) => {
  await openApp(page);
  await page.getByRole('button', { name: 'Saltar' }).click({ timeout: 15_000 });
  await expect(titulo(page, 'Iniciar sesión')).toBeVisible();

  await page.reload();
  await expect(titulo(page, 'Iniciar sesión')).toBeVisible({ timeout: 15_000 });
  await expect(titulo(page, 'Encuentra cuidadores cerca')).toHaveCount(0);
});

test('el favicon y el manifest usan la identidad de Doggo', async ({ page, request }) => {
  await openApp(page);
  await expect(page).toHaveTitle('Doggo');
  const manifest = await (await request.get('/manifest.json')).json();
  expect(manifest.name).toBe('Doggo');
  expect(manifest.theme_color).toBe('#FF8A38');
});
