# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
# Chart.js via esm.sh — all three pins must use the same CDN so that
# instanceof ArcElement checks inside chartjs-plugin-datalabels work correctly.
pin "chart.js", to: "https://esm.sh/chart.js@4.5.1"
pin "chart.js/helpers", to: "https://esm.sh/chart.js@4.5.1/helpers"
pin "@kurkle/color", to: "https://ga.jspm.io/npm:@kurkle/color@0.3.4/dist/color.esm.js"
pin "chartjs-plugin-datalabels", to: "https://esm.sh/chartjs-plugin-datalabels@2.2.0?external=chart.js"
