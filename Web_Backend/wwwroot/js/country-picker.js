// Searchable, flag-annotated dropdowns for Country and Nationality fields.
// Self-contained (no CDN) so the Student wizard and Profile page keep
// working offline. countriesData entries: [ISO-3166 alpha-2, country name,
// nationality/demonym]. Flags are rendered from the ISO code via Unicode
// regional indicator symbols, so no image assets are needed.
(function () {
    var countriesData = [
        ["AF", "Afghanistan", "Afghan"], ["AL", "Albania", "Albanian"], ["DZ", "Algeria", "Algerian"],
        ["AD", "Andorra", "Andorran"], ["AO", "Angola", "Angolan"], ["AG", "Antigua and Barbuda", "Antiguan"],
        ["AR", "Argentina", "Argentine"], ["AM", "Armenia", "Armenian"], ["AU", "Australia", "Australian"],
        ["AT", "Austria", "Austrian"], ["AZ", "Azerbaijan", "Azerbaijani"], ["BS", "Bahamas", "Bahamian"],
        ["BH", "Bahrain", "Bahraini"], ["BD", "Bangladesh", "Bangladeshi"], ["BB", "Barbados", "Barbadian"],
        ["BY", "Belarus", "Belarusian"], ["BE", "Belgium", "Belgian"], ["BZ", "Belize", "Belizean"],
        ["BJ", "Benin", "Beninese"], ["BT", "Bhutan", "Bhutanese"], ["BO", "Bolivia", "Bolivian"],
        ["BA", "Bosnia and Herzegovina", "Bosnian"], ["BW", "Botswana", "Botswanan"], ["BR", "Brazil", "Brazilian"],
        ["BN", "Brunei", "Bruneian"], ["BG", "Bulgaria", "Bulgarian"], ["BF", "Burkina Faso", "Burkinabe"],
        ["BI", "Burundi", "Burundian"], ["KH", "Cambodia", "Cambodian"], ["CM", "Cameroon", "Cameroonian"],
        ["CA", "Canada", "Canadian"], ["CV", "Cape Verde", "Cape Verdean"], ["CF", "Central African Republic", "Central African"],
        ["TD", "Chad", "Chadian"], ["CL", "Chile", "Chilean"], ["CN", "China", "Chinese"],
        ["CO", "Colombia", "Colombian"], ["KM", "Comoros", "Comoran"], ["CG", "Congo", "Congolese"],
        ["CR", "Costa Rica", "Costa Rican"], ["HR", "Croatia", "Croatian"], ["CU", "Cuba", "Cuban"],
        ["CY", "Cyprus", "Cypriot"], ["CZ", "Czech Republic", "Czech"], ["DK", "Denmark", "Danish"],
        ["DJ", "Djibouti", "Djiboutian"], ["DM", "Dominica", "Dominican"], ["DO", "Dominican Republic", "Dominican"],
        ["EC", "Ecuador", "Ecuadorian"], ["EG", "Egypt", "Egyptian"], ["SV", "El Salvador", "Salvadoran"],
        ["GQ", "Equatorial Guinea", "Equatorial Guinean"], ["ER", "Eritrea", "Eritrean"], ["EE", "Estonia", "Estonian"],
        ["SZ", "Eswatini", "Swazi"], ["ET", "Ethiopia", "Ethiopian"], ["FJ", "Fiji", "Fijian"],
        ["FI", "Finland", "Finnish"], ["FR", "France", "French"], ["GA", "Gabon", "Gabonese"],
        ["GM", "Gambia", "Gambian"], ["GE", "Georgia", "Georgian"], ["DE", "Germany", "German"],
        ["GH", "Ghana", "Ghanaian"], ["GR", "Greece", "Greek"], ["GD", "Grenada", "Grenadian"],
        ["GT", "Guatemala", "Guatemalan"], ["GN", "Guinea", "Guinean"], ["GW", "Guinea-Bissau", "Guinean"],
        ["GY", "Guyana", "Guyanese"], ["HT", "Haiti", "Haitian"], ["HN", "Honduras", "Honduran"],
        ["HK", "Hong Kong", "Hong Konger"], ["HU", "Hungary", "Hungarian"], ["IS", "Iceland", "Icelandic"],
        ["IN", "India", "Indian"], ["ID", "Indonesia", "Indonesian"], ["IR", "Iran", "Iranian"],
        ["IQ", "Iraq", "Iraqi"], ["IE", "Ireland", "Irish"], ["IL", "Israel", "Israeli"],
        ["IT", "Italy", "Italian"], ["JM", "Jamaica", "Jamaican"], ["JP", "Japan", "Japanese"],
        ["JO", "Jordan", "Jordanian"], ["KZ", "Kazakhstan", "Kazakhstani"], ["KE", "Kenya", "Kenyan"],
        ["KI", "Kiribati", "Kiribati"], ["KW", "Kuwait", "Kuwaiti"], ["KG", "Kyrgyzstan", "Kyrgyzstani"],
        ["LA", "Laos", "Laotian"], ["LV", "Latvia", "Latvian"], ["LB", "Lebanon", "Lebanese"],
        ["LS", "Lesotho", "Basotho"], ["LR", "Liberia", "Liberian"], ["LY", "Libya", "Libyan"],
        ["LI", "Liechtenstein", "Liechtensteiner"], ["LT", "Lithuania", "Lithuanian"], ["LU", "Luxembourg", "Luxembourgish"],
        ["MO", "Macao", "Macanese"], ["MG", "Madagascar", "Malagasy"], ["MW", "Malawi", "Malawian"],
        ["MY", "Malaysia", "Malaysian"], ["MV", "Maldives", "Maldivian"], ["ML", "Mali", "Malian"],
        ["MT", "Malta", "Maltese"], ["MH", "Marshall Islands", "Marshallese"], ["MR", "Mauritania", "Mauritanian"],
        ["MU", "Mauritius", "Mauritian"], ["MX", "Mexico", "Mexican"], ["FM", "Micronesia", "Micronesian"],
        ["MD", "Moldova", "Moldovan"], ["MC", "Monaco", "Monacan"], ["MN", "Mongolia", "Mongolian"],
        ["ME", "Montenegro", "Montenegrin"], ["MA", "Morocco", "Moroccan"], ["MZ", "Mozambique", "Mozambican"],
        ["MM", "Myanmar", "Burmese"], ["NA", "Namibia", "Namibian"], ["NR", "Nauru", "Nauruan"],
        ["NP", "Nepal", "Nepali"], ["NL", "Netherlands", "Dutch"], ["NZ", "New Zealand", "New Zealander"],
        ["NI", "Nicaragua", "Nicaraguan"], ["NE", "Niger", "Nigerien"], ["NG", "Nigeria", "Nigerian"],
        ["KP", "North Korea", "North Korean"], ["MK", "North Macedonia", "Macedonian"], ["NO", "Norway", "Norwegian"],
        ["OM", "Oman", "Omani"], ["PK", "Pakistan", "Pakistani"], ["PW", "Palau", "Palauan"],
        ["PS", "Palestine", "Palestinian"], ["PA", "Panama", "Panamanian"], ["PG", "Papua New Guinea", "Papua New Guinean"],
        ["PY", "Paraguay", "Paraguayan"], ["PE", "Peru", "Peruvian"], ["PH", "Philippines", "Filipino"],
        ["PL", "Poland", "Polish"], ["PT", "Portugal", "Portuguese"], ["QA", "Qatar", "Qatari"],
        ["RO", "Romania", "Romanian"], ["RU", "Russia", "Russian"], ["RW", "Rwanda", "Rwandan"],
        ["KN", "Saint Kitts and Nevis", "Kittitian"], ["LC", "Saint Lucia", "Saint Lucian"],
        ["VC", "Saint Vincent and the Grenadines", "Vincentian"], ["WS", "Samoa", "Samoan"], ["SM", "San Marino", "Sammarinese"],
        ["ST", "Sao Tome and Principe", "Sao Tomean"], ["SA", "Saudi Arabia", "Saudi"], ["SN", "Senegal", "Senegalese"],
        ["RS", "Serbia", "Serbian"], ["SC", "Seychelles", "Seychellois"], ["SL", "Sierra Leone", "Sierra Leonean"],
        ["SG", "Singapore", "Singaporean"], ["SK", "Slovakia", "Slovak"], ["SI", "Slovenia", "Slovenian"],
        ["SB", "Solomon Islands", "Solomon Islander"], ["SO", "Somalia", "Somali"], ["ZA", "South Africa", "South African"],
        ["KR", "South Korea", "South Korean"], ["SS", "South Sudan", "South Sudanese"], ["ES", "Spain", "Spanish"],
        ["LK", "Sri Lanka", "Sri Lankan"], ["SD", "Sudan", "Sudanese"], ["SR", "Suriname", "Surinamese"],
        ["SE", "Sweden", "Swedish"], ["CH", "Switzerland", "Swiss"], ["SY", "Syria", "Syrian"],
        ["TW", "Taiwan", "Taiwanese"], ["TJ", "Tajikistan", "Tajikistani"], ["TZ", "Tanzania", "Tanzanian"],
        ["TH", "Thailand", "Thai"], ["TL", "Timor-Leste", "Timorese"], ["TG", "Togo", "Togolese"],
        ["TO", "Tonga", "Tongan"], ["TT", "Trinidad and Tobago", "Trinidadian"], ["TN", "Tunisia", "Tunisian"],
        ["TR", "Turkey", "Turkish"], ["TM", "Turkmenistan", "Turkmen"], ["TV", "Tuvalu", "Tuvaluan"],
        ["UG", "Uganda", "Ugandan"], ["UA", "Ukraine", "Ukrainian"], ["AE", "United Arab Emirates", "Emirati"],
        ["GB", "United Kingdom", "British"], ["US", "United States", "American"], ["UY", "Uruguay", "Uruguayan"],
        ["UZ", "Uzbekistan", "Uzbekistani"], ["VU", "Vanuatu", "Vanuatuan"], ["VA", "Vatican City", "Vatican"],
        ["VE", "Venezuela", "Venezuelan"], ["VN", "Vietnam", "Vietnamese"], ["YE", "Yemen", "Yemeni"],
        ["ZM", "Zambia", "Zambian"], ["ZW", "Zimbabwe", "Zimbabwean"]
    ];

    // Windows/Chrome frequently renders Unicode regional-indicator flag
    // emoji as plain two-letter tiles instead of an actual flag, so flags
    // are SVGs (from the flag-icons package, copied into wwwroot/img/flags)
    // rather than emoji — identical rendering on every OS/browser.
    function flagUrl(iso) {
        return "/img/flags/" + iso.toLowerCase() + ".svg";
    }

    var countries = countriesData.map(function (row) {
        return { code: row[0], name: row[1], nationality: row[2], flagUrl: flagUrl(row[0]) };
    });

    // mode: "country" matches/displays the country name; "nationality" matches/displays the demonym.
    function initPicker(input, mode) {
        if (!input || input.dataset.pickerInit) return;
        input.dataset.pickerInit = "1";

        var labelOf = mode === "nationality"
            ? function (c) { return c.nationality; }
            : function (c) { return c.name; };

        input.setAttribute("autocomplete", "off");
        input.classList.add("country-picker-input");

        var wrap = document.createElement("div");
        wrap.className = "relative";
        input.parentNode.insertBefore(wrap, input);
        wrap.appendChild(input);

        var flagBadge = document.createElement("img");
        flagBadge.alt = "";
        flagBadge.className = "hidden absolute left-3 top-1/2 -translate-y-1/2 w-5 h-3.5 object-cover rounded-sm pointer-events-none";
        wrap.appendChild(flagBadge);
        input.classList.add("pl-10");

        function syncBadge() {
            var match = countries.find(function (c) { return labelOf(c).toLowerCase() === input.value.trim().toLowerCase(); });
            if (match) {
                flagBadge.src = match.flagUrl;
                flagBadge.classList.remove("hidden");
            } else {
                flagBadge.classList.add("hidden");
            }
        }

        var list = document.createElement("div");
        list.className = "country-picker-list hidden absolute z-30 mt-1 w-full max-h-56 overflow-y-auto rounded-xl border border-slate-200 dark:border-slate-600 bg-white dark:bg-slate-800 shadow-lg";
        wrap.appendChild(list);

        function render(filterText) {
            var q = (filterText || "").trim().toLowerCase();
            var matches = countries.filter(function (c) {
                return !q || labelOf(c).toLowerCase().indexOf(q) !== -1;
            }).slice(0, 50);

            list.innerHTML = "";
            if (!matches.length) {
                var empty = document.createElement("div");
                empty.className = "px-4 py-3 text-sm text-slate-400 dark:text-slate-500";
                empty.textContent = "No matches";
                list.appendChild(empty);
                return;
            }

            matches.forEach(function (c) {
                var row = document.createElement("button");
                row.type = "button";
                row.className = "w-full flex items-center gap-2 px-4 py-2 text-sm text-left text-slate-700 dark:text-slate-200 hover:bg-purple-50 dark:hover:bg-purple-950";
                row.innerHTML = "<img src=\"" + c.flagUrl + "\" alt=\"\" class=\"w-5 h-3.5 object-cover rounded-sm flex-shrink-0\" /><span>" + labelOf(c) + "</span>";
                row.addEventListener("mousedown", function (e) {
                    e.preventDefault();
                    input.value = labelOf(c);
                    input.dispatchEvent(new Event("change", { bubbles: true }));
                    syncBadge();
                    close();
                });
                list.appendChild(row);
            });
        }

        function open() {
            render(input.value);
            list.classList.remove("hidden");
        }
        function close() {
            list.classList.add("hidden");
        }

        input.addEventListener("focus", open);
        input.addEventListener("input", function () { render(input.value); list.classList.remove("hidden"); });
        input.addEventListener("blur", function () { setTimeout(close, 100); syncBadge(); });

        syncBadge();
    }

    function initAll(root) {
        (root || document).querySelectorAll("[data-country-picker]").forEach(function (el) {
            initPicker(el, "country");
        });
        (root || document).querySelectorAll("[data-nationality-picker]").forEach(function (el) {
            initPicker(el, "nationality");
        });
    }

    window.ProtonCountryPicker = { init: initAll };
    document.addEventListener("DOMContentLoaded", function () { initAll(document); });
})();
