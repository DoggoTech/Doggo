import { expect, Page } from '@playwright/test';

/** Abre la app y espera a que Flutter exponga el árbol de accesibilidad. */
export async function openApp(page: Page, path = '/') {
  await page.goto(path);
  await expect(page.locator('flutter-view')).toBeAttached({ timeout: 20_000 });
}
