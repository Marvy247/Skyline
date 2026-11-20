'use client'

import { useState, useEffect } from "react"
import Link from "next/link"
import { X, Menu, ArrowUpRight } from "lucide-react"
import { Logo } from "@/components/Logo"

const LINKS = [
  { href: "#problem", label: "Problem" },
  { href: "#mechanism", label: "Mechanism" },
  { href: "#features", label: "Features" },
  { href: "#demo", label: "Demo" },
]

export function Navbar() {
  const [scrolled, setScrolled] = useState(false)
  const [mounted, setMounted] = useState(false)
  const [menuOpen, setMenuOpen] = useState(false)

  useEffect(() => {
    setMounted(true)
    const handleScroll = () => setScrolled(window.scrollY > 40)
    window.addEventListener("scroll", handleScroll, { passive: true })
    return () => window.removeEventListener("scroll", handleScroll)
  }, [])

  return (
    <>
      <header
        className={`fixed top-0 left-0 right-0 z-50 flex items-center justify-between px-5 sm:px-8 py-4 transition-all duration-500 ${
          scrolled || menuOpen
            ? "bg-white/90 backdrop-blur-md border-b border-slate-200"
            : "bg-transparent"
        } ${mounted ? "opacity-100 translate-y-0" : "opacity-0 -translate-y-3"}`}
      >
        <Link href="/" className="flex items-center gap-2.5 shrink-0 group">
          <Logo size={32} />
          <span className="font-semibold text-slate-900 text-lg leading-none">Skyline</span>
          <span className="hidden sm:inline text-[10px] font-semibold uppercase tracking-widest text-sky-600 bg-sky-50 ring-1 ring-sky-200 rounded-full px-2 py-0.5">
            UHI11
          </span>
        </Link>

        <nav className="hidden md:flex items-center gap-8 text-sm text-slate-500">
          {LINKS.map((item) => (
            <a
              key={item.href}
              href={item.href}
              className="hover:text-slate-900 transition-colors duration-200 relative group"
            >
              {item.label}
              <span className="absolute -bottom-0.5 left-0 w-0 h-px bg-sky-400 group-hover:w-full transition-all duration-300" />
            </a>
          ))}
        </nav>

        <div className="flex items-center gap-3">
          <Link
            href="/dashboard"
            className="hidden sm:inline-flex items-center gap-1.5 rounded-xl bg-slate-900 px-4 py-2 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-slate-800"
          >
            Dashboard
            <ArrowUpRight className="h-3.5 w-3.5" />
          </Link>
          <button
            onClick={() => setMenuOpen((v) => !v)}
            className="md:hidden p-2 rounded-xl text-slate-600 hover:bg-slate-100 transition-colors"
            aria-label="Toggle menu"
          >
            {menuOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
          </button>
        </div>
      </header>

      {menuOpen ? (
        <div className="fixed inset-0 z-40 bg-white pt-24 md:hidden">
          <nav className="flex flex-col gap-6 px-8 text-lg font-medium text-slate-700">
            {LINKS.map((item) => (
              <a key={item.href} href={item.href} onClick={() => setMenuOpen(false)}>
                {item.label}
              </a>
            ))}
            <Link href="/dashboard" onClick={() => setMenuOpen(false)} className="text-sky-600">
              Dashboard →
            </Link>
          </nav>
        </div>
      ) : null}
    </>
  )
}
