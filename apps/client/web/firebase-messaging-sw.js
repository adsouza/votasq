// Service worker that handles FCM web push messages when the page is
// closed or in the background. Without this file the browser receives the
// FCM payload but has no handler to render the system notification.
//
// IMPORTANT: this runs in the service-worker scope, not the Flutter Dart
// VM — Dart/Flutter aren't available here. Keep it minimal.

// Use compat-mode SDKs because service workers don't support ESM imports
// from cross-origin servers without explicit type=module + CORS setup; the
// Firebase docs use the compat builds for this reason.
importScripts(
  'https://www.gstatic.com/firebasejs/12.4.0/firebase-app-compat.js',
);
importScripts(
  'https://www.gstatic.com/firebasejs/12.4.0/firebase-messaging-compat.js',
);

// Mirrors apps/client/lib/firebase_options.dart's `web` entry. Kept in
// sync by convention — if the values there change, update them here too.
firebase.initializeApp({
  apiKey: 'AIzaSyCYSIsIXqC4u0MyaVd07wTG-nvAIdnl7Hs',
  appId: '1:269624680910:web:33a9d10d05a7a28f124b9f',
  messagingSenderId: '269624680910',
  projectId: 'votasq',
  authDomain: 'votasq-190fd.firebaseapp.com',
});

const messaging = firebase.messaging();

// Renders a system notification when a push arrives while the page is in
// the background. FCM uses the `notification` block in the payload by
// default; this handler is the explicit hook in case you want to enrich
// the rendering with the structured `data` payload (e.g., a click action
// that deep-links into the app).
messaging.onBackgroundMessage((payload) => {
  const title = payload.notification?.title ?? 'Notification';
  const body = payload.notification?.body ?? '';
  self.registration.showNotification(title, {
    body,
    icon: '/favicon.png',
    data: payload.data ?? {},
  });
});
