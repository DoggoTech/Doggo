import { test, expect, Page } from '@playwright/test';
import {
  btn, enterAsOwner, goToLogin, scrollUntil, seen, switchDemo, tab, typeInto,
} from './helpers';

test.describe.configure({ timeout: 120_000 });

const MEET = 'https://meet.google.com/abc-defg-hij';

async function scheduleMeeting(page: Page, name: string) {
  const open = btn(page, `Agendar reunión con ${name}`);
  await scrollUntil(page, open);
  await open.click();
  await typeInto(page, 'Enlace de la videollamada', MEET);
  await btn(page, 'Guardar reunión').click();
  await expect(seen(page, new RegExp(`^Reunión con ${name} agendada para el`))).toBeVisible();
}

async function registerSitter(page: Page, name: string, email: string) {
  await goToLogin(page);
  await btn(page, 'Crear cuenta').click();
  await btn(page, 'Soy cuidador').click();
  await typeInto(page, 'Nombre completo', name);
  await typeInto(page, 'Correo', email);
  await typeInto(page, 'Contraseña', 'secreto1');
  await page.getByRole('checkbox').click();
  await page.getByRole('button', { name: 'Crear cuenta' }).last().click();
  await expect(seen(page, 'Tu perfil está en revisión')).toBeVisible();
}

test.describe('casos de verificación', () => {
  test('la admin ve sus casos, agenda la reunión, la marca hecha y aprueba sin confirmar', async ({ page }) => {
    await enterAsOwner(page);
    await switchDemo(page, 'Administrador');
    await expect(seen(page, 'Mis casos (2)')).toBeVisible();
    await expect(seen(page, 'Lo llevas tú')).toBeVisible();

    await scheduleMeeting(page, 'Natalia Peña');
    await expect(seen(page, /^Reunión: .* · sin confirmar$/)).toBeVisible();

    await btn(page, 'Marcar la reunión con Natalia Peña como hecha').click();
    await expect(seen(page, 'Reunión con Natalia Peña marcada como hecha')).toBeVisible();

    // Con la reunión hecha, aprobar no pide confirmación.
    await btn(page, 'Aprobar a Natalia Peña').click();
    await expect(seen(page, 'Natalia Peña fue aprobado')).toBeVisible();
    await expect(seen(page, 'Mis casos (1)')).toBeVisible();
  });

  test('el superadmin ve todos los casos y puede reasignarlos', async ({ page }) => {
    await enterAsOwner(page);
    await switchDemo(page, 'Superadministrador');
    await expect(seen(page, 'Todos (2)')).toBeVisible();
    await expect(seen(page, 'Lo lleva Ana Admin')).toBeVisible();
    await btn(page, 'Reasignar el caso de Natalia Peña').click();
    await page.getByText('Sergio Superadmin · Superadministrador').click();
    await expect(seen(page, 'El caso de Natalia Peña ahora lo lleva Sergio Superadmin')).toBeVisible();
  });

  test('el cuidador sube un certificado, la admin lo ve y agenda; el cuidador confirma', async ({ page }) => {
    await registerSitter(page, 'Celia Certificada', 'celia.cert@test.com');
    await expect(seen(page, 'Tu caso lo lleva Ana Admin, del equipo de Doggo.')).toBeVisible();

    // Certificado opcional: tipo, autorización y archivo.
    const upload = btn(page, 'Subir documento');
    await scrollUntil(page, upload);
    await upload.click();
    await page.getByRole('checkbox', { name: /^Autorizo a Doggo/ }).click();
    const chooser = page.waitForEvent('filechooser');
    await btn(page, 'Elegir archivo').click();
    await (await chooser).setFiles({
      name: 'curso-cuidado-animal.pdf',
      mimeType: 'application/pdf',
      buffer: Buffer.from('%PDF-1.4 certificado de prueba'),
    });
    await expect(seen(page, 'Documento subido')).toBeVisible();
    await expect(seen(page, 'curso-cuidado-animal.pdf')).toBeVisible();

    await switchDemo(page, 'Administrador');
    await expect(seen(page, 'Mis casos (3)')).toBeVisible();
    await scrollUntil(page, seen(page, '1 certificado'));
    await scheduleMeeting(page, 'Celia Certificada');

    // Vuelve a entrar con su cuenta: ve la reunión y confirma.
    await tab(page, 'Perfil').click();
    await scrollUntil(page, btn(page, 'Cerrar sesión'));
    await btn(page, 'Cerrar sesión').dispatchEvent('click');
    await typeInto(page, 'Correo', 'celia.cert@test.com');
    await typeInto(page, 'Contraseña', 'secreto1');
    await btn(page, 'Entrar').click();
    await expect(seen(page, /Videollamada el /)).toBeVisible();
    await expect(btn(page, 'Unirme a la reunión')).toBeVisible();
    await btn(page, 'Confirmar asistencia').click();
    await expect(seen(page, 'Confirmaste tu asistencia')).toBeVisible();
    await expect(btn(page, 'Confirmar asistencia')).toHaveCount(0);
  });
});
