import React from 'react';
import ImmutablePropTypes from 'react-immutable-proptypes';
import PropTypes from 'prop-types';
import ImmutablePureComponent from 'react-immutable-pure-component';
import { FormattedMessage } from 'react-intl';
import classNames from 'classnames';
import Icon from 'flavours/glitch/components/icon';

const filename = url => url.split('/').pop().split('#')[0].split('?')[0];

export default class AttachmentList extends ImmutablePureComponent {

  static propTypes = {
    media: ImmutablePropTypes.list.isRequired,
    compact: PropTypes.bool,
  };

  render () {
    const { media, compact } = this.props;

    return (
      <div className={classNames('attachment-list', { compact })}>
        {!compact && (
          <div className='attachment-list__icon'>
            <Icon id='link' />
          </div>
        )}

        <ul className='attachment-list__list'>
          {media.map(attachment => {
            const displayUrl = attachment.get('remote_url') || attachment.get('url');
            const description = attachment.get('description');

            return (
              <li key={attachment.get('id')}>
                <a href={displayUrl} target='_blank' rel='noopener noreferrer'>
                  {compact && <Icon id='link' />}
                  {compact && ' ' }
                  {description ? description : displayUrl ? filename(displayUrl) : <FormattedMessage id='attachments_list.unprocessed' defaultMessage='(unprocessed)' />}
                </a>
              </li>
            );
          })}
        </ul>
      </div>
    );
  }

}
