import type {Hook} from "../hook_composition"

type Mounted = {destroy(): void}

type CardCheckoutHook = {
  el: HTMLElement
  pushEventTo(target: HTMLElement, event: string, payload: object): void
  elements?: Mounted[]
  gone?: boolean
}

// Stripe's own form for one card or Link payment the panel opened
// (`AshTemplateWeb.CreditsPanel`): the email, which also finds the buyer's Link,
// then the card or Link itself. Stripe's script loads only here, on Continue.
// Pay goes straight to Stripe on every press; once Stripe says the payment went
// through, the panel adds the Credits. Stripe's words for a declined card or a
// missing field show below Pay.
export const CardCheckout: Hook = {
  async mounted(this: CardCheckoutHook) {
    const el = this.el
    const problem = el.querySelector<HTMLElement>("[data-problem]")!
    const pay = el.querySelector<HTMLButtonElement>("[data-pay]")!
    const say = (words: string) => { problem.textContent = words }

    const {loadStripe} = await import("@stripe/stripe-js/pure")
    const stripe = await loadStripe(el.dataset.publishableKey!).catch(() => null)
    if (this.gone) return
    if (!stripe) return say("Card payments couldn't load. Check your connection and try again.")

    const checkout = stripe.initCheckoutElementsSdk({
      clientSecret: el.dataset.clientSecret!,
      elementsOptions: {appearance: {theme: lightTheme() ? "stripe" : "night"}},
    })
    const contact = checkout.createContactDetailsElement()
    const payment = checkout.createPaymentElement()
    contact.mount(el.querySelector<HTMLElement>("[data-contact]")!)
    payment.mount(el.querySelector<HTMLElement>("[data-payment]")!)
    this.elements = [contact, payment]

    const loaded = await checkout.loadActions()
    if (this.gone) return
    if (loaded.type === "error") return say(loaded.error.message)

    pay.disabled = false
    pay.addEventListener("click", async () => {
      say("")
      const result = await loaded.actions.confirm({redirect: "if_required"})
      if (result.type === "success") this.pushEventTo(el, "card_paid", {})
      else say(result.error.message)
    })
  },

  destroyed(this: CardCheckoutHook) {
    this.gone = true
    this.elements?.forEach(element => element.destroy())
  },
}

// The site's own theme when the visitor chose one, else the device's.
function lightTheme(): boolean {
  const theme = document.documentElement.dataset.theme
  if (theme) return theme === "light"
  return window.matchMedia("(prefers-color-scheme: light)").matches
}
