export default {
  async fetch(request, env) {
    const token = request.headers.get("X-Proxy-Token");
    if (token !== env.PROXY_SECRET) {
      return new Response("Unauthorized", { status: 401 });
    }

    const url = new URL(request.url);
    const target = new URL("https://fapi.binance.com");
    target.pathname = url.pathname;
    target.search = url.search;

    const headers = new Headers(request.headers);
    headers.delete("X-Proxy-Token");

    return fetch(target.toString(), { method: "GET", headers });
  }
};
