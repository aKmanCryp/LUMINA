import type { Metadata } from "next";
import "./globals.css";
import "./reading.css";

export const metadata: Metadata = {
  title: "LÚMINA · Entre dos estrellas",
  description: "Una lectura para explorar su conexión por ₲29.000. Dos perfiles zodiacales, preguntas para conversar y PDF privado. Astrología recreativa. Vista previa para Paraguay.",
  robots: { index: false, follow: false },
  icons: {
    icon: "/favicon.svg",
    shortcut: "/favicon.svg",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="es-PY">
      <body className="antialiased">{children}</body>
    </html>
  );
}
