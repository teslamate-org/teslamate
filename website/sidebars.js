module.exports = {
  docs: [
    {
      type: "category",
      label: "Installation",
      items: [
        {
          type: "category",
          label: "Docker",
          link: { type: "doc", id: "installation/docker" },
          items: [
            {
              type: "category",
              label: "Reverse Proxy",
              items: [
                "advanced_guides/traefik",
                "advanced_guides/apache",
                "advanced_guides/unix_domain_sockets",
              ],
            },
            "advanced_guides/verifying_images",
          ],
        },
        "installation/nixos",
        "installation/tokens",
        {
          type: "category",
          label: "Unsupported methods",
          items: [
            "installation/unsupported/debian",
            "installation/unsupported/freebsd",
            "installation/unsupported/unraid",
          ],
        },
      ],
    },
    "faq",
    "screenshots",
    {
      type: "category",
      label: "Configuration",
      items: ["configuration/environment_variables", "configuration/api"],
    },
    {
      type: "category",
      label: "Import",
      items: ["import/teslafi", "import/tesla_apiscraper"],
    },
    {
      type: "category",
      label: "Integrations",
      items: [
        "integrations/home_assistant",
        "integrations/mqtt",
        "integrations/Node-RED",
      ],
    },
    {
      type: "category",
      label: "Maintenance",
      items: [
        "upgrading",
        "maintenance/backup",
        "maintenance/restore",
        "maintenance/upgrading_postgres",
        "maintenance/manually_fixing_data",
      ],
    },
    {
      type: "doc",
      id: "projects",
    },
    {
      type: "doc",
      id: "development",
    },
  ],
};
