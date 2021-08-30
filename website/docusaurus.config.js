module.exports = {
  title: "TeslaMate",
  tagline: "A self-hosted data logger for your Tesla 🚘",
  url: "https://docs.teslamate.org",
  baseUrl: "/",
  favicon: "img/favicon.ico",
  organizationName: "adriankumpf",
  projectName: "teslamate",
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
        // { to: "blog", label: "Blog", position: "left" },
        {
          href: "https://github.com/adriankumpf/teslamate",
          label: "GitHub",
          position: "right",
        },
      ],
    },
    // footer: {
    //   style: "dark",
    //   items: [
    //     {
    //       title: "Community",
    //       items: [
    //         {
    //           label: "Discord",
    //           href: "https://discordapp.com/invite/docusaurus",
    //         },
    //       ],
    //     },
    //   ],
    //   copyright: `Copyright © ${new Date().getFullYear()} Adrian Kumpf`,
    // },
    prism: {
      additionalLanguages: ["apacheconf", "sql"],
    },
  },
  presets: [
    [
      "@docusaurus/preset-classic",
      {
        docs: {
          // routeBasePath: "", // Docs-only
          sidebarCollapsible: false,
          sidebarPath: require.resolve("./sidebars.js"),
          editUrl:
            "https://github.com/adriankumpf/teslamate/edit/master/website/",
        },
        theme: {
          customCss: require.resolve("./src/css/custom.css"),
        },
      },
    ],
  ],
};
