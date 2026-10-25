import 'package:flutter/material.dart';

import 'info_page.dart';

class SafetyScreen extends StatelessWidget {
  const SafetyScreen({super.key});

  @override
  Widget build(BuildContext context) => const InfoPage(
    title: 'Seguridad y consejos',
    intro:
        'Doggo conecta a personas que no se conocen. Estas recomendaciones ayudan a que cada '
        'servicio salga bien para ti y para tu perro.',
    sections: [
      (
        'Para dueños',
        [
          'Revisa el perfil completo: reseñas, insignia "Verificado" y la bio del cuidador.',
          'Para el primer servicio, prefiere un paseo o una visita corta antes de un hospedaje.',
          'Escribe en las notas del perro sus medicinas, alergias y miedos: el cuidador las verá al aceptar.',
          'No compartas tu dirección exacta por fuera de la app: Doggo la muestra solo con la reserva aceptada.',
          'Paga y coordina siempre dentro de Doggo.',
        ],
      ),
      (
        'Para cuidadores',
        [
          'Lee las notas del perro antes de cada servicio y pregunta lo que no esté claro.',
          'Acepta solo los servicios y tamaños de perro que puedas atender bien.',
          'No aceptes pagos por fuera de Doggo ni pidas datos personales que la app no muestre.',
          'Si algo no se siente seguro, cancela y reporta. Tu seguridad va primero.',
        ],
      ),
      (
        'Cómo reportar',
        [
          'Usa el botón "Reportar" en el perfil del cuidador o en cualquier reserva.',
          'Elige el motivo: comportamiento inapropiado, perfil falso, cobro fuera de la app, maltrato animal u otro.',
          'El reporte es confidencial y lo revisa el equipo de Doggo, que puede suspender la cuenta reportada.',
          'Si hay un peligro inmediato para una persona o un animal, llama primero al 123.',
        ],
      ),
    ],
  );
}

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) => const InfoPage(
    title: 'Términos y condiciones',
    intro: 'Al crear una cuenta en Doggo aceptas estas condiciones.',
    sections: [
      (
        'Quién puede usar Doggo',
        [
          'Debes ser mayor de 18 años y dar información verdadera sobre ti y tus perros.',
          'Cada persona tiene una sola cuenta, como dueño o como cuidador.',
        ],
      ),
      (
        'El servicio',
        [
          'Doggo es una plataforma que conecta dueños con cuidadores independientes. Los cuidadores no son empleados de Doggo.',
          'Los cuidadores nuevos quedan en revisión hasta que un administrador los aprueba.',
          'Las reservas se solicitan, se aceptan y se pagan dentro de la app. Coordinar pagos por fuera está prohibido.',
        ],
      ),
      (
        'Conducta',
        [
          'Está prohibido el maltrato animal, el acoso, los perfiles falsos y compartir datos de contacto en textos públicos.',
          'Doggo puede suspender o eliminar cuentas que incumplan estas reglas, después de revisar los reportes.',
        ],
      ),
    ],
    footnote: 'Documento de ejemplo para el MVP. Antes de publicar la app debe revisarlo un abogado.',
  );
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) => const InfoPage(
    title: 'Política de privacidad',
    intro:
        'Tratamos tus datos personales conforme a la Ley 1581 de 2012 de Colombia y sus decretos '
        'reglamentarios.',
    sections: [
      (
        'Qué datos recogemos',
        [
          'Nombre, correo, rol (dueño o cuidador), foto y bio.',
          'Datos de tus perros, incluidas notas médicas y de comportamiento.',
          'Ubicación: en el mapa solo se muestra una ubicación aproximada (desplazada 200–300 m).',
          'Teléfono, dirección y ubicación exacta: privados.',
        ],
      ),
      (
        'Para qué los usamos',
        [
          'Mostrar cuidadores cerca, gestionar reservas y calificaciones, y mantener la seguridad de la comunidad.',
          'No vendemos tus datos ni los usamos para publicidad de terceros.',
        ],
      ),
      (
        'Quién los ve',
        [
          'Tu teléfono, tu dirección y las notas de tu perro solo los ve la otra persona de una reserva aceptada.',
          'Los administradores de Doggo ven la información necesaria para atender reportes y aprobar cuidadores.',
        ],
      ),
      (
        'Tus derechos',
        [
          'Puedes conocer, actualizar, rectificar y pedir la supresión de tus datos, y revocar tu autorización.',
          'Para ejercerlos escribe a privacidad@doggo.app. Respondemos en los plazos que fija la ley.',
        ],
      ),
    ],
    footnote: 'Documento de ejemplo para el MVP. Antes de publicar la app debe revisarlo un abogado.',
  );
}
