import { PaymentChannel, PaymentChannelJSON } from '../PaymentChannel'
import ChannelContract from '../ChannelContract'
import * as BigNumber from 'bignumber.js'
import { namespaced } from '../util/namespaced'
import IEngine from './IEngine'
import ChannelId from '../ChannelId'
import IChannelsDatabase from './IChannelsDatabase'
import log from '../util/log'

const LOG = log('AbstractChannelsDatabase')

export default abstract class AbstractChannelsDatabase<T extends IEngine> implements IChannelsDatabase {
  engine: T

  kind: string

  contract: ChannelContract

  constructor (engine: T, channelContract: ChannelContract, namespace: string | null) {
    this.kind = namespaced(namespace, 'channel')
    this.engine = engine
    this.contract = channelContract
  }

  inflatePaymentChannels (channels: Array<PaymentChannelJSON>): Promise<Array<PaymentChannel>> {
    if (!channels.length) {
      return Promise.resolve([])
    }

    // There shouldn't be any nulls here.
    return Promise.all(channels.map((chan: PaymentChannelJSON) => this.inflatePaymentChannel(chan))) as Promise<Array<PaymentChannel>>
  }

  async inflatePaymentChannel (json: PaymentChannelJSON): Promise<PaymentChannel | null> {
    if (!json) {
      return Promise.resolve(null)
    }

    const state = await this.contract.getState(json.channelId)
    const value = (await this.contract.channelById(json.channelId))[2]

    const doc = PaymentChannel.fromDocument(json)
    return new PaymentChannel(
      doc.sender,
      doc.receiver,
      doc.channelId,
      value,
      doc.spent,
      state === -1 ? 2 : state,
      doc.contractAddress || undefined
    )
  }

  filterByState (state: number, channels: PaymentChannel[]): PaymentChannel[] {
    return channels.filter((chan: PaymentChannel) => chan.state === state)
  }

  abstract save (paymentChannel: PaymentChannel): Promise<void>

  saveOrUpdate (paymentChannel: PaymentChannel): Promise<void> {
    LOG(`Saving or updating channel with ID ${paymentChannel.channelId.toString()}`)

    return this.firstById(paymentChannel.channelId).then((found: PaymentChannel | null) => {
      if (found) {
        LOG(`Spending channel with ID ${paymentChannel.channelId.toString()}`)
        return this.spend(paymentChannel.channelId, paymentChannel.spent)
      } else {
        LOG(`Spending channel with ID ${paymentChannel.channelId.toString()}`)
        return this.save(paymentChannel)
      }
    })
  }

  abstract deposit (channelId: ChannelId | string, value: BigNumber.BigNumber): Promise<void>

  abstract firstById (channelId: ChannelId | string): Promise<PaymentChannel | null>

  abstract spend (channelId: ChannelId | string, spent: BigNumber.BigNumber): Promise<void>

  abstract all (): Promise<Array<PaymentChannel>>

  abstract allOpen (): Promise<PaymentChannel[]>

  async allSettling (): Promise<PaymentChannel[]> {
    const all = await this.all()
    return this.filterByState(1, all)
  }

  abstract findUsable (sender: string, receiver: string, amount: BigNumber.BigNumber): Promise<PaymentChannel | null>

  abstract findBySenderReceiver (sender: string, receiver: string): Promise<Array<PaymentChannel>>

  abstract findBySenderReceiverChannelId (sender: string, receiver: string, channelId: ChannelId | string): Promise<PaymentChannel | null>

  abstract updateState (channelId: ChannelId | string, state: number): Promise<void>
}