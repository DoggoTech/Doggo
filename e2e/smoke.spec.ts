import { test, expect } from '@playwright/test';

test('la app web carga y Flutter monta la vista', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('flutter-view')).toBeAttached({ timeout: 20_000 });
});
