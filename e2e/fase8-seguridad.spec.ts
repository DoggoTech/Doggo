import { test, expect } from '@playwright/test';
import {
  bookWithCarlos, btn, enterAsOwner, goToHash, goToLogin, openProfileFromMap, openSitterProfile,
  scrollUntil, seen, switchDemo, tab, typeInto,
} from './helpers';

test.describe.configure({ timeout: 90_000 });

test.describe('reportar', () => {
  test('un dueño reporta a un cuidador desde su perfil', async ({ page }) => {
    await openSitterProfile(page, 'Laura Gómez');
    await btn(page, 'Reportar a Laura Gómez').click();
    await expect(btn(page, 'Enviar reporte')).toBeDisabled(); // falta el motivo
    await btn(page, 'Perfil falso').click();
    await typeInto(page, '¿Qué pasó? (opcional)', 'Las fotos parecen de internet');
    await btn(page, 'Enviar reporte').click();
    await expect(seen(page, 'Gracias por avisarnos')).toBeVisible();
    await btn(page, 'Listo').click();
    await expect(seen(page, 'Perfil del cuidador')).toBeVisible();
  });

  test('el dueño reporta desde una reserva', async ({ page }) => {
    await enterAsOwner(page);
    await bookWithCarlos(page);
    await tab(page, 'Reservas').click();
    await btn(page, 'Reportar').click();
    await btn(page, 'Cobro fuera de la app').click();
    await btn(page, 'Enviar reporte').click();
    await expect(seen(page, 'Gracias por avisarnos')).toBeVisible();
  });

  test('el cuidador reporta al dueño desde una solicitud', async ({ page }) => {
    await enterAsOwner(page);
    await bookWithCarlos(page);
    await switchDemo(page, 'Cuidador');
    await btn(page, 'Reportar a Daniela').click();
    await btn(page, 'Comportamiento inapropiado').click();
    await btn(page, 'Enviar reporte').click();
    await expect(seen(page, 'Gracias por avisarnos')).toBeVisible();
  });

  test('nadie puede reportarse a sí mismo', async ({ page }) => {
    await enterAsOwner(page);
    await switchDemo(page, 'Cuidador');
    await goToHash(page, '#/sitter/demo-sitter');
    await expect(seen(page, 'Perfil del cuidador')).toBeVisible();
    await expect(btn(page, 'Reportar a Carlos Cuidador')).toHaveCount(0);
  });
});

test.describe('seguridad, términos y privacidad', () => {
  test('consejos de seguridad desde el perfil', async ({ page }) => {
    await enterAsOwner(page);
    await tab(page, 'Perfil').click();
    await scrollUntil(page, seen(page, 'Seguridad y consejos'));
    await seen(page, 'Seguridad y consejos').click();
    await expect(seen(page, 'Para dueños')).toBeVisible();
    await expect(seen(page, 'Para cuidadores')).toBeVisible();
    await expect(seen(page, 'Cómo reportar')).toBeVisible();
    await scrollUntil(page, seen(page, /llama primero al 123/));
  });

  test('términos y privacidad se leen antes de crear la cuenta', async ({ page }) => {
    await goToLogin(page);
    await btn(page, 'Crear cuenta').click();
    await btn(page, 'Ver términos').click();
    await expect(seen(page, 'Términos y condiciones')).toBeVisible();
    await expect(seen(page, /mayor de 18 años/)).toBeVisible();
    await btn(page, 'Back').click();
    await btn(page, 'Ver política de privacidad').click();
    await expect(seen(page, /Ley 1581 de 2012/)).toBeVisible();
    await expect(seen(page, /ubicación aproximada/)).toBeVisible();
  });

  test('el perfil del cuidador avisa que se paga dentro de Doggo', async ({ page }) => {
    await openSitterProfile(page, 'Laura Gómez');
    await expect(seen(page, 'Paga y coordina solo dentro de Doggo.')).toBeVisible();
  });
});

test.describe('bio del cuidador', () => {
  test('rechaza datos de contacto y, al guardarla, el dueño la ve', async ({ page }) => {
    await enterAsOwner(page);
    await switchDemo(page, 'Cuidador');
    await tab(page, 'Perfil').click();
    await scrollUntil(page, btn(page, 'Guardar bio'));

    await typeInto(page, 'Tu bio', 'Escríbeme a carlos@gmail.com');
    await btn(page, 'Guardar bio').click();
    await expect(seen(page, /no compartas teléfonos, correos ni enlaces/)).toBeVisible();

    await typeInto(page, 'Tu bio', 'Paseos largos y mucho cariño en Chapinero.');
    await btn(page, 'Guardar bio').click();
    await expect(seen(page, 'Bio guardada')).toBeVisible();

    await switchDemo(page, 'Dueño');
    await openProfileFromMap(page, 'Carlos Cuidador');
    await expect(seen(page, /Paseos largos y mucho cariño en Chapinero\./)).toBeVisible();
  });
});
