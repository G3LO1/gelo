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
    // --- PORTFOLIO: FILTROWANIE + LIGHTBOX ---
    const portfolioGrid = document.getElementById('portfolioGrid');
    if (portfolioGrid) {
        const isEnPage = document.documentElement.lang === 'en';
        const filterButtons = document.querySelectorAll('.filter-btn');
        const items = Array.from(portfolioGrid.querySelectorAll('.portfolio-item'));

        // Komunikat o braku wyników
        const emptyMsg = document.createElement('p');
        emptyMsg.className = 'portfolio-empty';
        emptyMsg.hidden = true;
        emptyMsg.textContent = isEnPage
            ? 'No items in this category yet.'
            : 'Brak realizacji w tej kategorii.';
        portfolioGrid.appendChild(emptyMsg);

        // Aktualnie widoczne kafelki (dla nawigacji w lightboxie)
        let visibleItems = items.slice();

        const applyFilter = (category) => {
            visibleItems = [];
            items.forEach(item => {
                const match = category === 'all' || item.dataset.category === category;
                item.classList.toggle('is-hidden', !match);
                if (match) visibleItems.push(item);
            });
            emptyMsg.hidden = visibleItems.length > 0;
        };

        filterButtons.forEach(btn => {
            btn.addEventListener('click', () => {
                filterButtons.forEach(b => {
                    b.classList.remove('is-active');
                    b.setAttribute('aria-pressed', 'false');
                });
                btn.classList.add('is-active');
                btn.setAttribute('aria-pressed', 'true');
                applyFilter(btn.dataset.filter);
            });
        });

        // --- Lightbox ---
        const lightbox = document.getElementById('lightbox');
        const lbImg = lightbox.querySelector('.lightbox-img');
        const lbCaption = lightbox.querySelector('.lightbox-caption');
        const lbClose = lightbox.querySelector('.lightbox-close');
        const lbPrev = lightbox.querySelector('.lightbox-prev');
        const lbNext = lightbox.querySelector('.lightbox-next');
        let currentIndex = -1;
        let lastFocused = null;

        const showAt = (index) => {
            const list = visibleItems;
            if (!list.length) return;
            currentIndex = (index + list.length) % list.length;
            const item = list[currentIndex];
            const img = item.querySelector('img');
            const caption = item.dataset.caption || '';
            lbImg.src = img.src;
            lbImg.alt = img.alt || '';
            lbCaption.textContent = caption;
        };

        const openLightbox = (item) => {
            lastFocused = item;
            const index = visibleItems.indexOf(item);
            showAt(index === -1 ? 0 : index);
            lightbox.classList.add('is-open');
            document.body.style.overflow = 'hidden';
            lbClose.focus();
        };

        const closeLightbox = () => {
            lightbox.classList.remove('is-open');
            document.body.style.overflow = '';
            lbImg.src = '';
            if (lastFocused) lastFocused.focus();
        };

        items.forEach(item => {
            item.addEventListener('click', () => openLightbox(item));
        });

        lbClose.addEventListener('click', closeLightbox);
        lbPrev.addEventListener('click', () => showAt(currentIndex - 1));
        lbNext.addEventListener('click', () => showAt(currentIndex + 1));

        lightbox.addEventListener('click', (e) => {
            if (e.target === lightbox) closeLightbox();
        });

        document.addEventListener('keydown', (e) => {
            if (!lightbox.classList.contains('is-open')) return;
            if (e.key === 'Escape') closeLightbox();
            else if (e.key === 'ArrowLeft') showAt(currentIndex - 1);
            else if (e.key === 'ArrowRight') showAt(currentIndex + 1);
        });
    }

        // --- ROZWIJANE MENU "NASZA OFERTA" ---
    const dropdowns = document.querySelectorAll('.nav-dropdown');
    dropdowns.forEach(dd => {
        const toggle = dd.querySelector('.nav-dropdown-toggle');
        if (!toggle) return;
        toggle.addEventListener('click', () => {
            const open = dd.classList.toggle('is-open');
            toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
        });
    });
    document.addEventListener('click', (e) => {
        dropdowns.forEach(dd => {
            if (!dd.contains(e.target)) {
                dd.classList.remove('is-open');
                const t = dd.querySelector('.nav-dropdown-toggle');
                if (t) t.setAttribute('aria-expanded', 'false');
            }
        });
    });
    document.addEventListener('keydown', (e) => {
        if (e.key !== 'Escape') return;
        dropdowns.forEach(dd => {
            dd.classList.remove('is-open');
            const t = dd.querySelector('.nav-dropdown-toggle');
            if (t) t.setAttribute('aria-expanded', 'false');
        });
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
