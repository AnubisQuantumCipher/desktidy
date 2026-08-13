import type { Metadata, Viewport } from "next";
import "./globals.css";

const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL ?? "https://desktidy.vercel.app";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: "DeskTidy — Your Mac Desktop, Organized Automatically",
  description:
    "DeskTidy quietly files screenshots, documents, videos, code, and downloads into the right folders — locally on your Mac, without deleting or uploading anything.",
  keywords: [
    "mac desktop organizer",
    "macos file organization",
    "automatic desktop cleanup",
    "organize screenshots mac",
    "desktop clutter",
    "homebrew",
    "mac utility",
  ],
  alternates: { canonical: "/" },
  openGraph: {
    type: "website",
    url: SITE_URL,
    siteName: "DeskTidy",
    title: "DeskTidy — Your Mac Desktop, Organized Automatically",
    description:
      "Drop anything on your Desktop. DeskTidy waits until it's ready, files it in the right place, and tells you where it went. Local, safe, open source.",
    images: [{ url: "/og.png", width: 1200, height: 630, alt: "DeskTidy — a messy Mac Desktop transforming into tidy folders" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "DeskTidy — Your Mac Desktop, Organized Automatically",
    description:
      "Drop anything on your Desktop. DeskTidy files it in the right place and tells you where it went. Local, safe, open source.",
    images: ["/og.png"],
  },
  icons: {
    icon: [{ url: "/icon.svg", type: "image/svg+xml" }],
    apple: [{ url: "/apple-touch-icon.png", sizes: "180x180" }],
  },
  manifest: "/site.webmanifest",
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#fbfbf9" },
    { media: "(prefers-color-scheme: dark)", color: "#16181d" },
  ],
  width: "device-width",
  initialScale: 1,
};

const jsonLd = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: "DeskTidy",
  operatingSystem: "macOS 14 or later",
  applicationCategory: "UtilitiesApplication",
  offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
  description:
    "DeskTidy watches your Mac Desktop and files loose items into the right folders automatically — locally, without deleting or uploading anything.",
  url: SITE_URL,
  downloadUrl: "https://github.com/AnubisQuantumCipher/desktidy",
  softwareVersion: "1.1.2",
  license: "https://github.com/AnubisQuantumCipher/desktidy/blob/main/LICENSE",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>
        <a href="#main" className="skip-link">
          Skip to content
        </a>
        <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }} />
        {children}
      </body>
    </html>
  );
}
