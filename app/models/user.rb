# frozen_string_literal: true
# == Schema Information
#
# Table name: users
#
#  id                        :integer          not null, primary key
#  email                     :string           default(""), not null
#  account_id                :integer          not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  encrypted_password        :string           default(""), not null
#  reset_password_token      :string
#  reset_password_sent_at    :datetime
#  remember_created_at       :datetime
#  sign_in_count             :integer          default(0), not null
#  current_sign_in_at        :datetime
#  last_sign_in_at           :datetime
#  current_sign_in_ip        :inet
#  last_sign_in_ip           :inet
#  admin                     :boolean          default(FALSE)
#  confirmation_token        :string
#  confirmed_at              :datetime
#  confirmation_sent_at      :datetime
#  unconfirmed_email         :string
#  locale                    :string
#  encrypted_otp_secret      :string
#  encrypted_otp_secret_iv   :string
#  encrypted_otp_secret_salt :string
#  consumed_timestep         :integer
#  otp_required_for_login    :boolean
#  last_emailed_at           :datetime
#  otp_backup_codes          :string           is an Array
#  provider                  :string
#  uid                       :string
#  hide_oauth                :boolean          default(FALSE)
#  filtered_languages        :string           default([]), not null, is an Array
#

class User < ApplicationRecord
  include Settings::Extend
  ACTIVE_DURATION = 14.days

  devise :registerable, :recoverable,
         :rememberable, :trackable, :validatable, :confirmable,
         :two_factor_authenticatable, :two_factor_backupable,
         :omniauthable,
         otp_secret_encryption_key: ENV['OTP_SECRET'],
         otp_number_of_backup_codes: 10

  belongs_to :account, inverse_of: :user, required: true
  accepts_nested_attributes_for :account

  validates :locale, inclusion: I18n.available_locales.map(&:to_s), if: :locale?
  validates :email, email: true

  scope :recent,    -> { order(id: :desc) }
  scope :admins,    -> { where(admin: true) }
  scope :confirmed, -> { where.not(confirmed_at: nil) }
  scope :inactive, -> { where(arel_table[:current_sign_in_at].lt(ACTIVE_DURATION.ago)) }
  scope :matches_email, ->(value) { where(arel_table[:email].matches("#{value}%")) }
  scope :with_recent_ip_address, ->(value) { where(arel_table[:current_sign_in_ip].eq(value).or(arel_table[:last_sign_in_ip].eq(value))) }

  before_validation :sanitize_languages

  def confirmed?
    confirmed_at.present?
  end

  def disable_two_factor!
    self.otp_required_for_login = false
    otp_backup_codes&.clear
    save!
  end

  def send_devise_notification(notification, *args)
    devise_mailer.send(notification, self, *args).deliver_later
  end

  def setting_default_privacy
    settings.default_privacy || (account.locked? ? 'private' : 'public')
  end

  def setting_boost_modal
    settings.boost_modal
  end

  def setting_auto_play_gif
    settings.auto_play_gif
  end

  def self.find_from_oauth(auth)
    user = User.find_by(provider: auth.provider, uid: auth.uid)
    unless user
      password = SecureRandom.base64
      user = User.create(
        uid: auth.uid,
        provider: auth.provider,
        email: "#{auth.provider}-#{auth.uid}-dummy@example.com",
        password: password,
        password_confirmation: password,
        account_attributes: {
          username: auth.info.nickname
        }
      )
      user.confirm
    end

    user
  end

  def nico_url
    uid && !hide_oauth ? "http://www.nicovideo.jp/user/#{uid}" : nil
  end

  private

  def sanitize_languages
    filtered_languages.reject!(&:blank?)
  end
end
