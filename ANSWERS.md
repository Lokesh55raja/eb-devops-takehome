### Migration Plan from ingress-nginx to Gateway API

- **Step 1 – Check Existing Ingresses:** First, I will list all 40 Ingresses and check their configurations, especially annotations, because some annotations may not be supported in Gateway API.

- **Step 2 – Set Up New Controller:** I will install the new Gateway API controller alongside the existing ingress-nginx controller with a separate IP address. This will keep the current application running without any impact.

- **Step 3 – Convert the Routes:** I will use the `ingress2gateway` tool to convert the existing Ingresses into Gateway API routes. Then I will manually review each route to make sure everything is configured correctly.

- **Step 4 – Test the Application:** Before switching, I will send test requests to the new IP and compare the responses with the existing application to confirm everything is working properly.

- **Step 5 – Migrate Slowly:** I will move the hostnames in small batches instead of migrating everything at once. Before migration, I will reduce the DNS TTL so clients can pick up the new IP quickly. This will also help us switch back to the old IP faster if any issue occurs.

- **Step 6 – Remove Old Controller:** Once all applications are working properly and the rollback period is completed, I will remove the old ingress-nginx controller.

- **Possible Issues:** Some annotations may not have direct replacements. I will also check path-matching differences, TLS certificates across namespaces, client IP forwarding, IP-based allowlists, and which team is responsible for managing each route.

- **Why This Migration Is Important:** The ingress-nginx controller is reaching its end of life, so it will no longer receive security fixes or updates. We need to complete the migration to keep our applications secure and supported.
