module.exports = {
  docs: [
    {
      type: "category",
      label: "Installation",
      items: [
        "installation/docker",
        "installation/nixos",
        "advanced_guides/verifying_images",
        {
          type: "category",
          label: "Reverse Proxy",
          items: [
            "advanced_guides/traefik",
            "advanced_guides/apache",
            "advanced_guides/unix_domain_sockets",
          ],
        },
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
    {
      type: "category",
      label: "Post Installation",
      items: [
        "installation/tokens",
        "import/teslafi",
        "import/tesla_apiscraper",
        "integrations/home_assistant",
        "integrations/mqtt",
        "integrations/Node-RED",
      ],
    },
    "configuration/environment_variables",
    "configuration/api",
    {
      type: "category",
      label: "Maintenance",
      items: [
        "upgrading",
        "maintenance/backup",
        "maintenance/restore",
        "maintenance/manually_fixing_data",
        "maintenance/upgrading_postgres",
      ],
    },
    "faq",
    "screenshots",
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
