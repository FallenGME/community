import Component from "@glimmer/component";

export default class CttTopNavbar extends Component {
  <template>
    <div class="ctt-top-navbar" role="navigation" aria-label="Chris Titus Tech navigation">
      <div class="wrap">
        <div class="ctt-top-navbar__inner">
          <a
            class="ctt-top-navbar__brand"
            href="https://christitus.com"
            target="_blank"
            rel="noopener noreferrer"
          >
            Chris Titus Tech
          </a>

          <nav class="ctt-top-navbar__links" aria-label="Forum navigation links">
            <a href="/" class="ctt-top-navbar__link">Forum</a>
            <a href="/latest" class="ctt-top-navbar__link">Latest</a>
            <a href="/categories" class="ctt-top-navbar__link">Categories</a>
            <a href="/top" class="ctt-top-navbar__link ctt-top-navbar__link--desktop-only">Top</a>
            <a
              href="https://christitus.com"
              class="ctt-top-navbar__link ctt-top-navbar__link--primary"
              target="_blank"
              rel="noopener noreferrer"
            >
              Visit christitus.com
            </a>
          </nav>
        </div>
      </div>
    </div>
  </template>
}