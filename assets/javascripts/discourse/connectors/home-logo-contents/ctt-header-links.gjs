import Component from "@glimmer/component";

export default class CttHeaderLinks extends Component {
  <template>
    <nav class="ctt-header-nav" aria-label="Primary navigation">
      <a
        href="https://christitus.com"
        class="ctt-header-nav__link ctt-header-nav__link--primary"
        target="_blank"
        rel="noopener noreferrer"
      >
        Visit ChrisTitus.com
      </a>
    </nav>
  </template>
}
