document.addEventListener('DOMContentLoaded', () => {

    // --- MENU MOBILNE (hamburger) ---
    const navToggle = document.querySelector('.nav-toggle');
    const navLinks = document.querySelector('.nav-links');

    if (navToggle && navLinks) {
        navToggle.addEventListener('click', () => {
            const isOpen = navLinks.classList.toggle('is-open');
            navToggle.classList.toggle('is-open', isOpen);
            navToggle.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
            navToggle.setAttribute('aria-label', isOpen ? 'Zamknij menu' : 'Otwórz menu');
        });
    }

    // --- ANIMACJE PRZY SCROLLOWANIU ---
window.addEventListener('load', () => {    
    
    const observerOptions = {
        root: null,
        rootMargin: '0px',
        threshold: 0.05
    };


    const observer = new IntersectionObserver((entries, observer) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('is-visible');
                observer.unobserve(entry.target);
            }
        });
    }, observerOptions);

    const animatedElements = document.querySelectorAll('.scroll-animate');
    animatedElements.forEach(el => observer.observe(el));
});
    // --- OBSŁUGA FORMULARZA KONTAKTOWEGO (Formspree, bez przeładowania strony) ---
    const form = document.getElementById('contactForm');
    if (!form) return;

    const statusEl = document.getElementById('formStatus');
    const submitBtn = form.querySelector('.submit-btn');

    form.addEventListener('submit', async (e) => {
        e.preventDefault();

        // Wykrywanie języka na podstawie tagu <html>
        const isEn = document.documentElement.lang === 'en';
        
        const msgSending = isEn ? 'Sending...' : 'Wysyłanie...';
        const msgSuccess = isEn ? 'Thank you! Your message has been sent.' : 'Dziękujemy! Wiadomość została wysłana.';
        const msgTooMany = isEn ? 'Too many attempts. Please wait a moment and try again.' : 'Zbyt wiele prób. Odczekaj chwilę i spróbuj ponownie.';
        const msgError = isEn ? 'An error occurred. Please try again later.' : 'Wystąpił błąd. Spróbuj ponownie później.';
        const msgNetwork = isEn ? 'No connection. Check your internet and try again.' : 'Brak połączenia. Sprawdź internet i spróbuj ponownie.';

        const originalBtnText = submitBtn.textContent;
        submitBtn.disabled = true;
        submitBtn.textContent = msgSending;
        statusEl.textContent = '';
        statusEl.style.color = '';

        try {
            const response = await fetch(form.action, {
                method: 'POST',
                body: new FormData(form),
                headers: { 'Accept': 'application/json' }
            });

            if (response.ok) {
                statusEl.textContent = msgSuccess;
                statusEl.style.color = '#15803d';
                form.reset();
            } else if (response.status === 429) {
                statusEl.textContent = msgTooMany;
                statusEl.style.color = '#b91c1c';
            } else {
                const data = await response.json().catch(() => null);
                if (data && data.errors && data.errors.length) {
                    statusEl.textContent = data.errors.map(err => err.message).join(', ');
                } else {
                    statusEl.textContent = msgError;
                }
                statusEl.style.color = '#b91c1c';
            }
        } catch (error) {
            statusEl.textContent = msgNetwork;
            statusEl.style.color = '#b91c1c';
        } finally {
            submitBtn.disabled = false;
            submitBtn.textContent = originalBtnText;
        }
    });
});
