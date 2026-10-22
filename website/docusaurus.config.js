module.exports = {
  title: "TeslaMate",
  tagline: "A self-hosted data logger for your Tesla 🚘",
  url: "https://docs.teslamate.org",
  baseUrl: "/",
  favicon: "img/favicon.ico",
  organizationName: "teslamate-org",
  projectName: "teslamate",
  future: {
    v4: true,
  },
  storage: {
    type: "localStorage",
    namespace: true,
  },
  themeConfig: {
    navbar: {
      title: "TeslaMate",
      logo: {
        alt: "TeslaMate Logo",
        src: "img/logo.svg",
      },
      items: [
        {
          to: "docs/installation/docker",
          activeBasePath: "docs",
          label: "Docs",
          position: "left",
        },
        {
          href: "https://github.com/teslamate-org/teslamate",
          label: "GitHub",
          position: "right",
        },
      ],
    },
    prism: {
      additionalLanguages: ["apacheconf", "sql"],
    },
  },
  presets: [
    [
      "@docusaurus/preset-classic",
      {
        docs: {
          sidebarCollapsible: false,
          sidebarPath: require.resolve("./sidebars.js"),
          editUrl:
            "https://github.com/teslamate-org/teslamate/edit/main/website/",
        },
        theme: {
          customCss: require.resolve("./src/css/custom.css"),
        },
      },
    ],
  ],
  plugins: [
    [
      "@docusaurus/plugin-client-redirects",
      {
        redirects: [
          {
            from: "/docs/maintenance/backup_restore",
            to: "/docs/maintenance/backup",
          },
        ],
      },
    ],
  ],
};
