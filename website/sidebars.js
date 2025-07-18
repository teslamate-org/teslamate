module.exports = {
  docs: [
    {
      type: "category",
      label: "Getting started",
      items: [
        {
          type: "category",
          label: "Installation",
          items: [
            "installation/docker",
            "installation/nixos",
            {
              type: "category",
              label: "unsupported Installation methods",
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
      ],
    },
    {
      type: "category",
      label: "Advanced Guides",
      items: [
        "advanced_guides/traefik",
        "advanced_guides/apache",
        "advanced_guides/unix_domain_sockets",
      ],
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
      label: "Advanced Configuration",
      items: ["configuration/environment_variables", "configuration/api"],
    },
    {
      type: "category",
      label: "Maintenance",
      items: [
        "upgrading",
        "maintenance/backup_restore",
        "maintenance/manually_fixing_data",
        "maintenance/upgrading_postgres",
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
