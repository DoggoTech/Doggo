import { test, expect, Page } from '@playwright/test';
import { bookWithCarlos, btn, enterAsOwner, openProfileFromMap, scrollUntil, seen, switchDemo, tab, typeInto } from './helpers';

test.describe.configure({ timeout: 90_000 });

/** Como cuidador, responde (o completa) la solicitud y vuelve al dueño en "Reservas". */
async function sitterDoes(page: Page, ...actions: ('Aceptar' | 'Rechazar' | 'Marcar completada')[]) {
  await switchDemo(page, 'Cuidador');
  for (const a of actions) {
    if (a === 'Marcar completada') await tab(page, 'Agenda').click();
    await btn(page, a).click();
    await expect(seen(page, a === 'Aceptar' ? 'Reserva aceptada' : a === 'Rechazar' ? 'Solicitud rechazada' : 'Reserva completada')).toBeVisible();
  }
  await switchDemo(page, 'Dueño');
  await tab(page, 'Reservas').click();
}

test.describe('mis reservas (dueño)', () => {
  test('pendiente con contador y sin contacto; al aceptarse muestra el contacto del cuidador', async ({ page }) => {
    await enterAsOwner(page);
    await bookWithCarlos(page);
    await tab(page, 'Reservas').click();

    await expect(seen(page, 'Paseo con Carlos Cuidador')).toBeVisible();
    await expect(seen(page, 'Estado: Pendiente')).toBeVisible();
    await expect(seen(page, /^Carlos responde en (1 h \d+ min|2 h)$/)).toBeVisible();
    await expect(seen(page, 'Verás su teléfono y dirección cuando acepte.')).toBeVisible();
    await expect(seen(page, /Contacto de Carlos/)).toHaveCount(0);

    await sitterDoes(page, 'Aceptar');
    await expect(seen(page, 'Estado: Aceptada')).toBeVisible();
    await expect(seen(page, /Contacto de Carlos Cuidador/)).toBeVisible();
    await expect(seen(page, /Teléfono: 300 123 4567/)).toBeVisible();
    await expect(seen(page, /Dirección: Carrera 7 #60-20, Chapinero/)).toBeVisible();
  });

  test('el cuidador ve el contacto del dueño y las notas del perro solo tras aceptar', async ({ page }) => {
    await enterAsOwner(page);
    await bookWithCarlos(page);
    await switchDemo(page, 'Cuidador');
    await expect(seen(page, 'Daniela Dueña · Rocky')).toBeVisible();
    await expect(seen(page, /Notas de Rocky/)).toHaveCount(0);
    await expect(seen(page, /310 987 6543/)).toHaveCount(0);

    await btn(page, 'Aceptar').click();
    await tab(page, 'Agenda').click();
    await expect(seen(page, /Contacto de Daniela Dueña/)).toBeVisible();
    await expect(seen(page, /Teléfono: 310 987 6543/)).toBeVisible();
    await expect(seen(page, /Notas de Rocky: Muy juguetón/)).toBeVisible();
  });

  test('cancelar una reserva la pasa a Canceladas', async ({ page }) => {
    await enterAsOwner(page);
    await bookWithCarlos(page);
    await tab(page, 'Reservas').click();
    await btn(page, 'Cancelar reserva').click();
    await btn(page, 'Sí, cancelar').click();
    await expect(seen(page, 'Reserva cancelada')).toBeVisible();
    await expect(seen(page, 'No tienes reservas próximas.')).toBeVisible();
    await btn(page, 'Canceladas (1)').click();
    await expect(seen(page, 'Estado: Cancelada')).toBeVisible();
    await expect(btn(page, 'Cancelar reserva')).toHaveCount(0);
  });

  test('una solicitud rechazada aparece en Canceladas como Rechazada', async ({ page }) => {
    await enterAsOwner(page);
    await bookWithCarlos(page);
    await sitterDoes(page, 'Rechazar');
    await btn(page, 'Canceladas (1)').click();
    await expect(seen(page, 'Estado: Rechazada')).toBeVisible();
  });

  test('calificar una reserva completada: una sola vez y se ve en el perfil', async ({ page }) => {
    await enterAsOwner(page);
    await bookWithCarlos(page);
    await sitterDoes(page, 'Aceptar', 'Marcar completada');
    await btn(page, 'Pasadas (1)').click();
    await expect(seen(page, 'Estado: Completada')).toBeVisible();

    await btn(page, 'Calificar a Carlos').click();
    await btn(page, '5 estrellas').click();
    await typeInto(page, 'Comentario (opcional)', 'Puntual y cariñoso');
    await btn(page, 'Enviar reseña').click();
    await expect(seen(page, '¡Gracias por tu reseña!')).toBeVisible();
    await expect(seen(page, 'Ya calificaste esta reserva')).toBeVisible();
    await expect(btn(page, 'Calificar a Carlos')).toHaveCount(0);

    await tab(page, 'Explorar').click();
    await openProfileFromMap(page, 'Carlos Cuidador');
    await expect(seen(page, 'Reseñas (1)')).toBeVisible();
    await expect(seen(page, /^Reseña de Daniela D\., 5 de 5\. Puntual y cariñoso/)).toBeVisible();
  });

  test('una reseña con un teléfono se rechaza', async ({ page }) => {
    await enterAsOwner(page);
    await bookWithCarlos(page);
    await sitterDoes(page, 'Aceptar', 'Marcar completada');
    await btn(page, 'Pasadas (1)').click();
    await btn(page, 'Calificar a Carlos').click();
    await btn(page, '4 estrellas').click();
    await typeInto(page, 'Comentario (opcional)', 'Escríbeme al 300 111 2233');
    await btn(page, 'Enviar reseña').click();
    await expect(seen(page, /no compartas teléfonos, correos ni enlaces/)).toBeVisible();
  });
});

test.describe('mis perros', () => {
  test('agregar, editar y borrar un perro', async ({ page }) => {
    await enterAsOwner(page);
    await tab(page, 'Perros').click();
    await expect(seen(page, /^Rocky/)).toBeVisible();
    await expect(seen(page, /^Luna/)).toBeVisible();

    await btn(page, 'Agregar perro').click();
    await expect(page.getByRole('alertdialog')).toBeVisible();
    await page.waitForTimeout(400);
    await typeInto(page, 'Nombre del perro', 'Max');
    await btn(page, 'Gigante').click();
    await typeInto(page, 'Notas médicas o de comportamiento (opcional)', 'Toma pastilla a las 8');
    await btn(page, 'Guardar').click();
    await expect(seen(page, /^Max/)).toBeVisible();
    await expect(seen(page, /Notas: Toma pastilla a las 8/)).toBeVisible();

    await btn(page, 'Editar a Luna').click();
    await expect(page.getByRole('alertdialog')).toBeVisible();
    await page.waitForTimeout(400);
    await typeInto(page, 'Nombre del perro', 'Luna Bella');
    await btn(page, 'Guardar').click();
    await expect(seen(page, /^Luna Bella/)).toBeVisible();

    await btn(page, 'Borrar a Max').click();
    await btn(page, 'Sí, borrar').click();
    await expect(seen(page, 'Max fue borrado')).toBeVisible();
    await expect(seen(page, /^Max\b/)).toHaveCount(0);
  });

  test('las notas no pueden llevar correos ni teléfonos', async ({ page }) => {
    await enterAsOwner(page);
    await tab(page, 'Perros').click();
    await btn(page, 'Editar a Rocky').click();
    await expect(page.getByRole('alertdialog')).toBeVisible();
    await page.waitForTimeout(400);
    await typeInto(page, 'Notas médicas o de comportamiento (opcional)', 'escríbeme a daniela@gmail.com');
    await btn(page, 'Guardar').click();
    await expect(seen(page, /no compartas teléfonos, correos ni enlaces/)).toBeVisible();
  });

  test('no se puede borrar un perro con una reserva activa', async ({ page }) => {
    await enterAsOwner(page);
    await bookWithCarlos(page);
    await tab(page, 'Perros').click();
    await btn(page, 'Borrar a Rocky').click();
    await btn(page, 'Sí, borrar').click();
    await expect(seen(page, 'No puedes borrar un perro con reservas activas.')).toBeVisible();
    await expect(seen(page, /^Rocky/)).toBeVisible();
  });
});

test.describe('mis datos de contacto', () => {
  test('se validan y se guardan desde el perfil', async ({ page }) => {
    await enterAsOwner(page);
    await tab(page, 'Perfil').click();
    await scrollUntil(page, btn(page, 'Guardar contacto'));
    await typeInto(page, 'Teléfono', 'llámame');
    await btn(page, 'Guardar contacto').click();
    await expect(seen(page, /Escribe un teléfono válido/)).toBeVisible();
    await typeInto(page, 'Teléfono', '311 222 3344');
    await btn(page, 'Guardar contacto').click();
    await expect(seen(page, 'Datos de contacto guardados')).toBeVisible();
  });
});
