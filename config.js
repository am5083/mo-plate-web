// Backend URL for live availability checks.
//
// Empty by default so the app still runs as a generator if a backend doesn't exist
// For local dev, append ?api=http://localhost:8080 to the URL.
//
// The GitHub Pages workflow overwrites this line from the `BACKEND_URL` repo
// variable, in this case I'm using Fly.io
window.MO_PLATE_API = "";
